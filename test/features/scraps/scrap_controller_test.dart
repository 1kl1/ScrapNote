import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/scraps/scrap_controller.dart';
import 'package:scrapnote/infrastructure/platform/location_capture.dart';
import 'package:scrapnote/infrastructure/vault/vault_repository.dart';

void main() {
  late Directory sandbox;
  late Directory supportDirectory;
  late Directory vaultDirectory;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scrapnote_controller_');
    supportDirectory = Directory('${sandbox.path}/support');
    vaultDirectory = Directory('${sandbox.path}/vault');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  ScrapController buildController({
    Future<String?> Function()? picker,
    Future<String?> Function()? restorer,
    ScrapLocationProvider? locationProvider,
  }) {
    var sequence = 0;
    return ScrapController(
      directoryPicker: picker ?? () async => vaultDirectory.path,
      directoryRestorer: restorer ?? () async => null,
      supportDirectoryProvider: () async => supportDirectory,
      locationProvider: locationProvider ?? () async => null,
      repositoryFactory: (root) => VaultRepository(
        root,
        idGenerator: () => 'scrap-${sequence++}',
        now: () => DateTime.utc(2026, 9, 4, 8, sequence),
      ),
    );
  }

  test('selects a vault and persists a new scrap', () async {
    final controller = buildController();

    await controller.initialize();
    expect(controller.hasVault, isFalse);

    final saved = await controller.saveScrap('# 첫 생각');

    expect(saved, isTrue);
    expect(controller.vaultPath, vaultDirectory.path);
    expect(controller.scraps.single.firstLineTitle, '첫 생각');
    expect(
      File('${supportDirectory.path}/settings.json').readAsStringSync(),
      contains(vaultDirectory.path),
    );
    expect(
      await Directory('${vaultDirectory.path}/scraps')
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.md'))
          .length,
      1,
    );
  });

  test('restores the saved vault path on the next launch', () async {
    final first = buildController();
    await first.initialize();
    await first.saveScrap('다시 만날 메모');

    final restored = buildController();
    await restored.initialize();

    expect(restored.hasVault, isTrue);
    expect(restored.scraps.single.body, '다시 만날 메모');
  });

  test('persists an image-only scrap', () async {
    final attachment = File('${sandbox.path}/desk.jpg');
    await attachment.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
    final controller = buildController();
    await controller.initialize();

    final saved = await controller.saveScrap(
      '',
      attachmentPaths: <String>[attachment.path],
    );

    expect(saved, isTrue);
    expect(controller.scraps.single.assets.single.originalName, 'desk.jpg');
    expect(controller.scraps.single.body, startsWith('![desk.jpg]('));
  });

  test('keeps an empty scrap out of the vault', () async {
    final controller = buildController();
    await controller.initialize();

    final saved = await controller.saveScrap('  \n ');

    expect(saved, isFalse);
    expect(controller.hasVault, isFalse);
    expect(controller.errorMessage, contains('빈 Scrap'));
  });

  test('captures location metadata on the first save', () async {
    final capturedAt = DateTime.utc(2026, 9, 4, 8);
    final location = ScrapLocation(
      latitude: 37.5665,
      longitude: 126.978,
      accuracyMeters: 8,
      source: 'gps',
      capturedAt: capturedAt,
    );
    final controller = buildController(locationProvider: () async => location);
    await controller.initialize();

    await controller.saveScrap('Located thought');

    expect(controller.scraps.single.location, location);
  });

  test('saveDocument updates an existing scrap and returns it', () async {
    final controller = buildController();
    await controller.initialize();
    final original = await controller.saveDocument('Original');

    final updated = await controller.saveDocument('Edited', existing: original);

    expect(original, isNotNull);
    expect(updated, isNotNull);
    expect(updated!.id, original!.id);
    expect(updated.createdAt, original.createdAt);
    expect(updated.body, 'Edited');
    expect(controller.scraps, hasLength(1));
    expect(controller.scraps.single, updated);
    expect(
      await Directory('${vaultDirectory.path}/scraps')
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.md'))
          .length,
      1,
    );
  });

  test('does not connect a vault when the picker is cancelled', () async {
    final controller = buildController(picker: () async => null);
    await controller.initialize();

    final selected = await controller.chooseVault();

    expect(selected, isFalse);
    expect(controller.hasVault, isFalse);
  });
}
