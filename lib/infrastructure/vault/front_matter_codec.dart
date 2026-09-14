import 'dart:convert';

import 'package:scrapnote/domain/scrap.dart';
import 'package:yaml/yaml.dart';

/// Encodes and decodes the human-readable Markdown representation of a scrap.
class ScrapFileCodec {
  const ScrapFileCodec();

  static const schema = 'scrapnote/v1';
  static const type = 'scrap';

  String encode(Scrap scrap) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('schema: ${_quoted(schema)}')
      ..writeln('type: ${_quoted(type)}')
      ..writeln('id: ${_quoted(scrap.id)}')
      ..writeln('created_at: ${_quoted(_date(scrap.createdAt))}')
      ..writeln('updated_at: ${_quoted(_date(scrap.updatedAt))}');

    if (scrap.localDate case final localDate?) {
      buffer.writeln('local_date: ${_quoted(localDate)}');
    }
    if (scrap.utcOffsetMinutes case final utcOffsetMinutes?) {
      buffer.writeln('utc_offset_minutes: $utcOffsetMinutes');
    }
    if (scrap.timezoneName case final timezoneName?) {
      buffer.writeln('timezone_name: ${_quoted(timezoneName)}');
    }

    if (scrap.assets.isEmpty) {
      buffer.writeln('assets: []');
    } else {
      buffer.writeln('assets:');
      for (final asset in scrap.assets) {
        buffer
          ..writeln('  - hash: ${_quoted(asset.hash)}')
          ..writeln('    relative_path: ${_quoted(asset.relativePath)}')
          ..writeln('    original_name: ${_quoted(asset.originalName)}')
          ..writeln('    mime_type: ${_quoted(asset.mimeType)}');
      }
    }

    final location = scrap.location;
    if (location != null) {
      buffer
        ..writeln('location:')
        ..writeln('  latitude: ${location.latitude}')
        ..writeln('  longitude: ${location.longitude}')
        ..writeln('  accuracy_meters: ${location.accuracyMeters}')
        ..writeln('  source: ${_quoted(location.source)}')
        ..writeln('  captured_at: ${_quoted(_date(location.capturedAt))}');
    }

    buffer
      ..writeln('---')
      ..write(scrap.body);
    return buffer.toString();
  }

  Scrap decode(String contents) {
    final document = _splitDocument(contents);

    late final Object? loaded;
    try {
      loaded = loadYaml(document.frontMatter);
    } on YamlException catch (error) {
      throw FormatException('Invalid YAML front matter: ${error.message}');
    }

    if (loaded is! Map) {
      throw const FormatException('Front matter must be a YAML mapping.');
    }

    final map = loaded;
    final actualSchema = _requiredString(map, 'schema');
    if (actualSchema != schema) {
      throw FormatException(
        'Unsupported scrap schema "$actualSchema"; expected "$schema".',
      );
    }

    final actualType = _requiredString(map, 'type');
    if (actualType != type) {
      throw FormatException(
        'Expected a "$type" document, found "$actualType".',
      );
    }

    return Scrap(
      id: _requiredString(map, 'id'),
      body: document.body,
      createdAt: _requiredDate(map, 'created_at'),
      updatedAt: _requiredDate(map, 'updated_at'),
      localDate: _optionalLocalDate(map, 'local_date'),
      utcOffsetMinutes: _optionalUtcOffsetMinutes(map, 'utc_offset_minutes'),
      timezoneName: _optionalString(map, 'timezone_name'),
      assets: _assets(map['assets']),
      location: _location(map['location']),
    );
  }

  static String _date(DateTime value) => value.toUtc().toIso8601String();

  // JSON strings are valid YAML scalars and safely cover quotes, colons,
  // Unicode, and file names that resemble YAML booleans or numbers.
  static String _quoted(String value) => jsonEncode(value);

  static _FrontMatterDocument _splitDocument(String contents) {
    var source = contents;
    if (source.startsWith('\uFEFF')) {
      source = source.substring(1);
    }

    final firstLineEnd = _lineEnd(source, 0);
    if (firstLineEnd == null ||
        source.substring(0, firstLineEnd).trim() != '---') {
      throw const FormatException(
        'Scrap file must begin with a YAML front matter delimiter.',
      );
    }

    var cursor = _afterLineEnd(source, firstLineEnd);
    final yamlStart = cursor;
    while (cursor <= source.length) {
      final lineEnd = _lineEnd(source, cursor) ?? source.length;
      if (source.substring(cursor, lineEnd).trim() == '---') {
        var bodyStart = lineEnd;
        if (bodyStart < source.length) {
          bodyStart = _afterLineEnd(source, bodyStart);
        }
        return _FrontMatterDocument(
          source.substring(yamlStart, cursor),
          source.substring(bodyStart),
        );
      }

      if (lineEnd == source.length) {
        break;
      }
      cursor = _afterLineEnd(source, lineEnd);
    }

    throw const FormatException(
      'YAML front matter is missing its closing delimiter.',
    );
  }

  static int? _lineEnd(String source, int start) {
    if (start > source.length) {
      return null;
    }
    final newline = source.indexOf('\n', start);
    if (newline == -1) {
      return start == 0 && source.isEmpty ? null : source.length;
    }
    return newline > start && source.codeUnitAt(newline - 1) == 13
        ? newline - 1
        : newline;
  }

  static int _afterLineEnd(String source, int lineEnd) {
    var cursor = lineEnd;
    if (cursor < source.length && source.codeUnitAt(cursor) == 13) {
      cursor += 1;
    }
    if (cursor < source.length && source.codeUnitAt(cursor) == 10) {
      cursor += 1;
    }
    return cursor;
  }

  static String _requiredString(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'Front matter field "$key" must be a non-empty string.',
      );
    }
    return value;
  }

  static DateTime _requiredDate(Map<dynamic, dynamic> map, String key) {
    final raw = _requiredString(map, key);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException(
        'Front matter field "$key" is not an ISO-8601 date.',
      );
    }
    return parsed.toUtc();
  }

  static String? _optionalString(Map<dynamic, dynamic> map, String key) {
    if (!map.containsKey(key)) {
      return null;
    }
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'Front matter field "$key" must be a non-empty string.',
      );
    }
    return value;
  }

  static String? _optionalLocalDate(Map<dynamic, dynamic> map, String key) {
    final value = _optionalString(map, key);
    if (value == null) {
      return null;
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException(
        'Front matter field "$key" must use YYYY-MM-DD format.',
      );
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw FormatException('Front matter field "$key" is not a valid date.');
    }
    return value;
  }

  static int? _optionalUtcOffsetMinutes(Map<dynamic, dynamic> map, String key) {
    if (!map.containsKey(key)) {
      return null;
    }
    final value = map[key];
    final parsed = switch (value) {
      int number => number,
      String text => int.tryParse(text),
      _ => null,
    };
    if (parsed == null || parsed < -1440 || parsed > 1440) {
      throw FormatException(
        'Front matter field "$key" must be an integer UTC offset in minutes.',
      );
    }
    return parsed;
  }

  static List<ScrapAsset> _assets(Object? value) {
    if (value == null) {
      return const <ScrapAsset>[];
    }
    if (value is! List) {
      throw const FormatException(
        'Front matter field "assets" must be a list.',
      );
    }

    return List<ScrapAsset>.unmodifiable(
      value.map((entry) {
        if (entry is! Map) {
          throw const FormatException('Every asset must be a YAML mapping.');
        }
        final hash = _requiredString(entry, 'hash').toLowerCase();
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
          throw const FormatException(
            'Asset hash must be a 64-character hexadecimal SHA-256 digest.',
          );
        }
        return ScrapAsset(
          hash: hash,
          relativePath: _requiredString(entry, 'relative_path'),
          originalName: _requiredString(entry, 'original_name'),
          mimeType: _requiredString(entry, 'mime_type'),
        );
      }),
    );
  }

  static ScrapLocation? _location(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      throw const FormatException(
        'Front matter field "location" must be a mapping.',
      );
    }

    final latitude = _requiredDouble(value, 'latitude');
    final longitude = _requiredDouble(value, 'longitude');
    final accuracy = _requiredDouble(value, 'accuracy_meters');
    if (latitude < -90 || latitude > 90) {
      throw const FormatException(
        'Location latitude must be between -90 and 90.',
      );
    }
    if (longitude < -180 || longitude > 180) {
      throw const FormatException(
        'Location longitude must be between -180 and 180.',
      );
    }
    if (accuracy < 0) {
      throw const FormatException('Location accuracy cannot be negative.');
    }

    return ScrapLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
      source: _requiredString(value, 'source'),
      capturedAt: _requiredDate(value, 'captured_at'),
    );
  }

  static double _requiredDouble(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw FormatException('Front matter field "$key" must be a number.');
  }
}

class _FrontMatterDocument {
  const _FrontMatterDocument(this.frontMatter, this.body);

  final String frontMatter;
  final String body;
}
