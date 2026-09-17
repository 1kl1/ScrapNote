import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'sync_manifest.dart';

typedef SyncVaultSummaryLoader =
    Future<SyncVaultSummary> Function(String vaultPath);

Future<SyncVaultSummary> loadSyncVaultSummary(String vaultPath) =>
    SyncVaultSummary.load(Directory(vaultPath));

/// A read-only snapshot of the local data covered by personal sync.
class SyncVaultSummary {
  const SyncVaultSummary({
    required this.scrapCount,
    required this.noteCount,
    required this.assetCount,
    required this.expenseCount,
    required this.fileCount,
    required this.totalBytes,
    required this.syncedItemCount,
    this.lastSyncedAt,
  });

  static const empty = SyncVaultSummary(
    scrapCount: 0,
    noteCount: 0,
    assetCount: 0,
    expenseCount: 0,
    fileCount: 0,
    totalBytes: 0,
    syncedItemCount: 0,
  );

  final int scrapCount;
  final int noteCount;
  final int assetCount;
  final int expenseCount;
  final int fileCount;
  final int totalBytes;
  final int syncedItemCount;
  final DateTime? lastSyncedAt;

  static Future<SyncVaultSummary> load(Directory root) async {
    var scrapCount = 0;
    var noteCount = 0;
    var assetCount = 0;
    var expenseCount = 0;
    var fileCount = 0;
    var totalBytes = 0;

    for (final folder in const ['scraps', 'notes', 'assets', 'expenses']) {
      final directory = Directory(path.join(root.path, folder));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = path
            .relative(entity.path, from: root.path)
            .split(path.separator)
            .join('/');
        try {
          validateSyncPath(relative);
        } on FormatException {
          continue;
        }
        final bytes = await entity.length();
        fileCount += 1;
        totalBytes += bytes;
        if (relative.startsWith('scraps/')) {
          scrapCount += 1;
        } else if (relative.startsWith('notes/')) {
          noteCount += 1;
        } else if (relative.startsWith('assets/')) {
          assetCount += 1;
        } else if (relative.startsWith('expenses/') &&
            relative != 'expenses/.settings/summary.json') {
          expenseCount += 1;
        }
      }
    }

    var syncedItemCount = 0;
    DateTime? lastSyncedAt;
    final state = File(path.join(root.path, '.sync', 'state.json'));
    if (await state.exists()) {
      try {
        final decoded = jsonDecode(await state.readAsString());
        if (decoded is Map<String, dynamic>) {
          final entries = decoded['entries'];
          if (entries is Map) {
            syncedItemCount = entries.values
                .where((value) => value != directoryDigest)
                .length;
          }
          final rawSyncedAt = decoded['synced_at'];
          if (rawSyncedAt is String) {
            lastSyncedAt = DateTime.tryParse(rawSyncedAt)?.toUtc();
          }
        }
      } on FormatException {
        // A damaged sync state must not hide valid local Vault statistics.
      }
    }

    return SyncVaultSummary(
      scrapCount: scrapCount,
      noteCount: noteCount,
      assetCount: assetCount,
      expenseCount: expenseCount,
      fileCount: fileCount,
      totalBytes: totalBytes,
      syncedItemCount: syncedItemCount,
      lastSyncedAt: lastSyncedAt,
    );
  }
}
