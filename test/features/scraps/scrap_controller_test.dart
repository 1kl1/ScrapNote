import 'dart:async';
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
    LocationPermissionSettingsOpener? locationSettingsOpener,
  }) {
    var sequence = 0;
    return ScrapController(
      directoryPicker: picker ?? () async => vaultDirectory.path,
      directoryRestorer: restorer ?? () async => null,
      supportDirectoryProvider: () async => supportDirectory,
      locationProvider: locationProvider ?? () async => null,
      locationSettingsOpener: locationSettingsOpener ?? () async => true,
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

  test('ignores a duplicate save while location capture is running', () async {
    final locationRequest = Completer<ScrapLocation?>();
    var locationRequests = 0;
    final controller = buildController(
      locationProvider: () {
        locationRequests += 1;
        return locationRequest.future;
      },
    );
    await controller.initialize();
    expect(await controller.chooseVault(), isTrue);

    final firstSave = controller.saveDocument('Only once');
    final duplicateSave = controller.saveDocument('Only once');

    expect(await duplicateSave, isNull);
    expect(locationRequests, 1);
    locationRequest.complete(null);
    expect(await firstSave, isNotNull);
    expect(controller.scraps, hasLength(1));
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

  test('retries missing location for an existing scrap', () async {
    final captured = ScrapLocation(
      latitude: 37.5665,
      longitude: 126.978,
      accuracyMeters: 9,
      source: 'device',
      capturedAt: DateTime.utc(2026, 9, 15),
    );
    var attempts = 0;
    final controller = buildController(
      locationProvider: () async {
        attempts += 1;
        return attempts == 1 ? null : captured;
      },
    );
    await controller.initialize();
    final original = await controller.saveDocument('Missing location');

    final updated = await controller.captureLocationForScrap(original!);

    expect(updated?.location, captured);
    expect(controller.scraps.single.location, captured);
    expect(controller.scraps.single.body, 'Missing location');
  });

  test('reports a failed location retry without changing the scrap', () async {
    final controller = buildController(locationProvider: () async => null);
    await controller.initialize();
    final original = await controller.saveDocument('Still local');

    expect(await controller.captureLocationForScrap(original!), isNull);
    expect(controller.errorMessage, contains('수동으로 지정'));
    expect(controller.scraps.single.location, isNull);
  });

  test('persists a manually selected location', () async {
    final controller = buildController();
    await controller.initialize();
    final original = await controller.saveDocument('Manual place');
    final manual = ScrapLocation(
      latitude: 34.011286,
      longitude: -116.166868,
      accuracyMeters: 0,
      source: 'manual',
      capturedAt: DateTime.utc(2026, 9, 15),
    );

    final updated = await controller.setLocationForScrap(original!, manual);

    expect(updated?.location, manual);
    expect(controller.scraps.single.location, manual);
  });

  test('opens app settings for a permanently denied location', () async {
    var opens = 0;
    final controller = buildController(
      locationSettingsOpener: () async {
        opens += 1;
        return true;
      },
    );

    expect(await controller.openLocationPermissionSettings(), isTrue);
    expect(opens, 1);
    expect(controller.errorMessage, isNull);
  });

  test('does not connect a vault when the picker is cancelled', () async {
    final controller = buildController(picker: () async => null);
    await controller.initialize();

    final selected = await controller.chooseVault();

    expect(selected, isFalse);
    expect(controller.hasVault, isFalse);
  });
}
