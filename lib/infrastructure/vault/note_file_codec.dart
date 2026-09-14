import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../../domain/note.dart';
import '../../domain/scrap.dart';

class NoteFileCodec {
  const NoteFileCodec();

  static const schema = 'scrapnote/v1';
  static const type = 'note';

  String encode(Note note) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('schema: ${jsonEncode(schema)}')
      ..writeln('type: ${jsonEncode(type)}')
      ..writeln('id: ${jsonEncode(note.id)}')
      ..writeln('title: ${jsonEncode(note.title)}')
      ..writeln('folder: ${jsonEncode(note.folder)}')
      ..writeln(
        'created_at: ${jsonEncode(note.createdAt.toUtc().toIso8601String())}',
      )
      ..writeln(
        'updated_at: ${jsonEncode(note.updatedAt.toUtc().toIso8601String())}',
      );
    if (note.assets.isEmpty) {
      buffer.writeln('assets: []');
    } else {
      buffer.writeln('assets:');
      for (final asset in note.assets) {
        buffer
          ..writeln('  - hash: ${jsonEncode(asset.hash)}')
          ..writeln('    relative_path: ${jsonEncode(asset.relativePath)}')
          ..writeln('    original_name: ${jsonEncode(asset.originalName)}')
          ..writeln('    mime_type: ${jsonEncode(asset.mimeType)}');
      }
    }
    buffer
      ..writeln('---')
      ..write(note.body);
    return buffer.toString();
  }

  Note decode(String contents, {required String filePath}) {
    final split = _split(contents);
    late final Object? loaded;
    try {
      loaded = loadYaml(split.$1);
    } on YamlException catch (error) {
      throw FormatException('Invalid Note front matter: ${error.message}');
    }
    if (loaded is! Map) {
      throw const FormatException('Note front matter must be a mapping.');
    }
    if (_string(loaded, 'schema') != schema ||
        _string(loaded, 'type') != type) {
      throw const FormatException('Unsupported Note document.');
    }
    return Note(
      id: _string(loaded, 'id'),
      body: split.$2,
      title: _optionalString(loaded, 'title') ?? '',
      folder: _optionalString(loaded, 'folder') ?? '',
      createdAt: _date(loaded, 'created_at'),
      updatedAt: _date(loaded, 'updated_at'),
      filePath: filePath,
      assets: _assets(loaded['assets']),
    );
  }

  static (String, String) _split(String source) {
    final match = RegExp(
      r'^---\r?\n([\s\S]*?)\r?\n---\r?\n?',
    ).firstMatch(source);
    if (match == null) {
      throw const FormatException('Note file must contain YAML front matter.');
    }
    return (match.group(1)!, source.substring(match.end));
  }

  static String _string(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Note field "$key" must be a non-empty string.');
    }
    return value;
  }

  static String? _optionalString(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    return value is String ? value : null;
  }

  static DateTime _date(Map<dynamic, dynamic> map, String key) {
    final value = DateTime.tryParse(_string(map, key));
    if (value == null) {
      throw FormatException('Note field "$key" must be an ISO-8601 date.');
    }
    return value.toUtc();
  }

  static List<ScrapAsset> _assets(Object? value) {
    if (value == null) {
      return const <ScrapAsset>[];
    }
    if (value is! List) {
      throw const FormatException('Note assets must be a list.');
    }
    return List<ScrapAsset>.unmodifiable(
      value.map((entry) {
        if (entry is! Map) {
          throw const FormatException('Every Note asset must be a mapping.');
        }
        return ScrapAsset(
          hash: _string(entry, 'hash'),
          relativePath: _string(entry, 'relative_path'),
          originalName: _string(entry, 'original_name'),
          mimeType: _string(entry, 'mime_type'),
        );
      }),
    );
  }
}
