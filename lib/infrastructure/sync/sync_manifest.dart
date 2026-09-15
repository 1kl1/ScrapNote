import 'package:flutter/foundation.dart';

const directoryDigest = 'directory';

class SyncManifest {
  SyncManifest(this.revision, Map<String, String> entries)
    : entries = Map.unmodifiable(entries) {
    for (final entry in entries.entries) {
      validateSyncPath(entry.key);
      if (entry.value != directoryDigest &&
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value)) {
        throw const FormatException('Invalid sync digest.');
      }
      if (entry.key.startsWith('notes/') &&
          entry.value != directoryDigest &&
          !entry.key.endsWith('.md')) {
        throw const FormatException('Only Markdown notes may be synchronized.');
      }
      if (entry.value == directoryDigest && !entry.key.startsWith('notes/')) {
        throw const FormatException('Only note folders may be synchronized.');
      }
    }
  }
  final int revision;
  final Map<String, String> entries;
}

void validateSyncPath(String value) {
  final parts = value.split('/');
  if (parts.length < 2 ||
      parts.any(
        (s) =>
            s.isEmpty ||
            s == '.' ||
            s == '..' ||
            s.contains(RegExp(r'[\\:\x00-\x1f]')),
      )) {
    throw const FormatException('Unsafe sync path.');
  }
  final allowed = switch (parts.first) {
    'scraps' =>
      value.endsWith('.md') && !parts.skip(1).any((s) => s.startsWith('.')),
    'notes' => !parts.skip(1).any((s) => s.startsWith('.')),
    'assets' => parts.length == 4 && parts[1] == 'sha256',
    'expenses' =>
      value == 'expenses/.settings/summary.json' ||
          (parts.length == 2 &&
              parts.last.endsWith('.json') &&
              !parts.last.startsWith('.')),
    _ => false,
  };
  if (!allowed || value.endsWith('.tmp')) {
    throw const FormatException('This file is outside the synchronized vault.');
  }
}

class SyncConflict {
  const SyncConflict(this.path, this.local, this.remote);
  final String path;
  final String? local;
  final String? remote;
}

class SyncResolution {
  const SyncResolution(this.conflict, {required this.useLocal});
  final SyncConflict conflict;
  final bool useLocal;
}

class SyncConflicts implements Exception {
  const SyncConflicts(this.files);
  final List<SyncConflict> files;
}

/// Three-way merge: absent paths represent deletion only after a shared baseline.
Map<String, String> mergeManifests(
  Map<String, String> base,
  Map<String, String> local,
  Map<String, String> remote, {
  Map<String, SyncResolution> resolutions = const {},
}) {
  final merged = <String, String>{};
  final conflicts = <SyncConflict>[];
  for (final name in {...base.keys, ...local.keys, ...remote.keys}) {
    final l = local[name], r = remote[name], b = base[name];
    String? chosen;
    if (l == r) {
      chosen = l;
    } else if (l == b) {
      chosen = r;
    } else if (r == b) {
      chosen = l;
    } else {
      final resolution = resolutions[name];
      if (resolution != null &&
          resolution.conflict.local == l &&
          resolution.conflict.remote == r) {
        chosen = resolution.useLocal ? l : r;
      } else {
        conflicts.add(SyncConflict(name, l, r));
      }
    }
    if (chosen != null) merged[name] = chosen;
  }
  if (conflicts.isNotEmpty) throw SyncConflicts(conflicts);
  // A retained/new child keeps its parents, even after a concurrent folder deletion.
  for (final name in merged.keys.toList()) {
    if (!name.startsWith('notes/')) continue;
    var parent = name.substring(0, name.lastIndexOf('/'));
    while (parent != 'notes') {
      merged[parent] = directoryDigest;
      parent = parent.substring(0, parent.lastIndexOf('/'));
    }
  }
  return merged;
}

bool sameManifest(Map<String, String> a, Map<String, String> b) =>
    mapEquals(a, b);
