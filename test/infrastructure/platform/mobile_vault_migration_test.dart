import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/infrastructure/platform/mobile_vault_migration.dart';

void main() {
  late Directory support;
  setUp(
    () async =>
        support = await Directory.systemTemp.createTemp('mobile-migration-'),
  );
  tearDown(() async => support.delete(recursive: true));
  test(
    'keeps the legacy Vault and opens a separate empty Vault for Oracle',
    () async {
      final state = File('${support.path}/vault/.sync/state.json');
      await state.parent.create(recursive: true);
      await state.writeAsString(
        jsonEncode({
          'identity': 'https://old.supabase.co/owner',
          'entries': {},
        }),
      );
      final old = File('${support.path}/vault/scraps/old.md');
      await old.parent.create(recursive: true);
      await old.writeAsString('old mobile content');
      final selected = await resolveMobileVaultDirectory(support);
      expect(selected.path, '${support.path}/vault-oracle');
      expect(await selected.list().isEmpty, isTrue);
      expect(await old.readAsString(), 'old mobile content');
      expect((await resolveMobileVaultDirectory(support)).path, selected.path);
    },
  );
  test(
    'new installations, local-only files and invalid state retain their Vault',
    () async {
      expect(
        (await resolveMobileVaultDirectory(support)).path,
        '${support.path}/vault',
      );
      final state = File('${support.path}/vault/.sync/state.json');
      await state.parent.create(recursive: true);
      for (final value in [
        'invalid json',
        '{}',
        jsonEncode({'identity': 'https://api.example/owner'}),
      ]) {
        await state.writeAsString(value);
        expect(
          (await resolveMobileVaultDirectory(support)).path,
          '${support.path}/vault',
        );
      }
    },
  );
}
