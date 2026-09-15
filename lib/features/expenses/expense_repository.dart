import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'expense_record.dart';
import 'expense_settings.dart';

class ExpenseRepository {
  ExpenseRepository(this.root);
  final Directory root;
  Directory get directory => Directory(path.join(root.path, 'expenses'));

  File get _settingsFile =>
      File(path.join(directory.path, '.settings', 'summary.json'));

  Future<ExpenseSettings> loadSettings() async {
    if (!await _settingsFile.exists()) return const ExpenseSettings();
    final data = jsonDecode(await _settingsFile.readAsString());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid expense settings.');
    }
    return ExpenseSettings.fromJson(data);
  }

  Future<void> saveSettings(ExpenseSettings settings) async {
    await _settingsFile.parent.create(recursive: true);
    final temporary = File('${_settingsFile.path}.tmp');
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temporary.rename(_settingsFile.path);
  }

  Future<List<ExpenseRecord>> load() async {
    await directory.create(recursive: true);
    final records = <ExpenseRecord>[];
    await for (final file in directory.list(followLinks: false)) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) {
        throw FormatException(
          'Invalid expense file: ${path.basename(file.path)}',
        );
      }
      records.add(ExpenseRecord.fromJson(data));
    }
    return records;
  }

  File _file(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid expense identifier.');
    }
    return File(path.join(directory.path, '$id.json'));
  }

  Future<void> save(ExpenseRecord record) async {
    await directory.create(recursive: true);
    final file = _file(record.id);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<void> delete(ExpenseRecord record) async {
    final file = _file(record.id);
    final trash = Directory(path.join(root.path, '.trash', 'expenses'));
    await trash.create(recursive: true);
    await file.rename(
      path.join(
        trash.path,
        '${DateTime.now().microsecondsSinceEpoch}-${path.basename(file.path)}',
      ),
    );
  }
}
