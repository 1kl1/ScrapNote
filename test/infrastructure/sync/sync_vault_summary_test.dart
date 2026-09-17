import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:scrapnote/infrastructure/sync/sync_vault_summary.dart';

void main() {
  late Directory vault;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('sync-summary-');
  });

  tearDown(() async {
    if (await vault.exists()) await vault.delete(recursive: true);
  });

  Future<void> write(String relative, String contents) async {
    final file = File(path.join(vault.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  test('reports local sync scope and persisted completion time', () async {
    await write('scraps/a.md', 'scrap');
    await write('notes/trips/n.md', 'note');
    await write('assets/sha256/ab/hash.png', 'image');
    await write('expenses/one.json', '{}');
    await write('expenses/.settings/summary.json', '{}');
    await write('notes/.draft.md', 'private');
    await write('.trash/old.md', 'private');
    await write(
      '.sync/state.json',
      jsonEncode({
        'identity': 'server/user',
        'entries': {
          'scraps/a.md': List.filled(64, 'a').join(),
          'notes/trips': 'directory',
          'notes/trips/n.md': List.filled(64, 'b').join(),
        },
        'synced_at': '2026-09-15T18:20:00Z',
      }),
    );

    final summary = await SyncVaultSummary.load(vault);

    expect(summary.scrapCount, 1);
    expect(summary.noteCount, 1);
    expect(summary.assetCount, 1);
    expect(summary.expenseCount, 1);
    expect(summary.fileCount, 5);
    expect(summary.totalBytes, greaterThan(0));
    expect(summary.syncedItemCount, 2);
    expect(summary.lastSyncedAt, DateTime.utc(2026, 9, 15, 18, 20));
  });
}
