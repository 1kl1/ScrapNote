import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/infrastructure/vault/front_matter_codec.dart';
import 'package:scrapnote/infrastructure/vault/vault_repository.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'scrapnote-vault-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'initialize creates the canonical scrap and asset directories',
    () async {
      final root = Directory(p.join(temporaryDirectory.path, 'vault'));
      final repository = VaultRepository(root);

      await repository.initialize();

      expect(await Directory(p.join(root.path, 'scraps')).exists(), isTrue);
      expect(
        await Directory(p.join(root.path, 'assets', 'sha256')).exists(),
        isTrue,
      );
    },
  );

  test('createScrap writes an atomic Markdown source file', () async {
    final fixedTime = DateTime(2026, 9, 4, 4, 5, 6, 7);
    final repository = VaultRepository(
      temporaryDirectory,
      idGenerator: () => 'scrap-1',
      now: () => fixedTime,
    );

    final created = await repository.createScrap('A quick thought');
    final files = await repository.scrapsDirectory.list().toList();

    expect(created.id, 'scrap-1');
    expect(created.createdAt, fixedTime.toUtc());
    expect(created.localDate, '2026-09-04');
    expect(created.utcOffsetMinutes, fixedTime.timeZoneOffset.inMinutes);
    expect(created.timezoneName, fixedTime.timeZoneName);
    expect(created.localCalendarDate, DateTime(2026, 9, 4));
    expect(files.whereType<File>(), hasLength(1));
    expect(
      p.basename(files.whereType<File>().single.path),
      contains('scrap-1'),
    );
    expect(files.any((entity) => entity.path.endsWith('.tmp')), isFalse);

    final source = await files.whereType<File>().single.readAsString();
    expect(source, contains('local_date: "2026-09-04"'));
    expect(
      source,
      contains('utc_offset_minutes: ${fixedTime.timeZoneOffset.inMinutes}'),
    );
    expect(source, contains('timezone_name: "${fixedTime.timeZoneName}"'));
    expect(const ScrapFileCodec().decode(source), created);
  });

  test('attachments are hashed, deduplicated, and linked relatively', () async {
    final first = File(p.join(temporaryDirectory.path, 'first photo.png'));
    final second = File(p.join(temporaryDirectory.path, 'copy.png'));
    final bytes = <int>[137, 80, 78, 71, 1, 2, 3, 4];
    await first.writeAsBytes(bytes);
    await second.writeAsBytes(bytes);

    final vault = Directory(p.join(temporaryDirectory.path, 'vault'));
    final repository = VaultRepository(
      vault,
      idGenerator: () => 'with-image',
      now: () => DateTime.utc(2026, 9, 4),
    );

    final scrap = await repository.createScrap(
      'Photo note',
      attachmentPaths: [first.path, second.path],
    );

    final expectedHash = sha256.convert(bytes).toString();
    expect(scrap.assets, hasLength(1));
    expect(scrap.assets.single.hash, expectedHash);
    expect(
      scrap.assets.single.relativePath,
      '../assets/sha256/${expectedHash.substring(0, 2)}/$expectedHash.png',
    );
    expect(
      scrap.body,
      contains(
        '![first photo.png]'
        '(../assets/sha256/${expectedHash.substring(0, 2)}/$expectedHash.png)',
      ),
    );

    final storedAssets = await repository.assetsDirectory
        .list(recursive: true)
        .where((entity) => entity is File && !entity.path.endsWith('.tmp'))
        .toList();
    expect(storedAssets, hasLength(1));
    expect(await (storedAssets.single as File).readAsBytes(), bytes);
  });

  test('listScraps returns most recently modified scraps first', () async {
    final times = <DateTime>[
      DateTime.utc(2026, 9, 3),
      DateTime.utc(2026, 9, 4),
    ];
    final ids = <String>['older', 'newer'];
    final repository = VaultRepository(
      temporaryDirectory.path,
      idGenerator: () => ids.removeAt(0),
      now: () => times.removeAt(0),
    );

    await repository.createScrap('Older');
    await repository.createScrap('Newer');

    final scraps = await repository.listScraps();
    expect(scraps.map((scrap) => scrap.id), ['newer', 'older']);
  });

  test('editing an older scrap moves it to the front', () async {
    final times = <DateTime>[
      DateTime.utc(2026, 9, 1),
      DateTime.utc(2026, 9, 2),
      DateTime.utc(2026, 9, 3),
    ];
    final ids = <String>['first', 'second'];
    final repository = VaultRepository(
      temporaryDirectory.path,
      idGenerator: () => ids.removeAt(0),
      now: () => times.removeAt(0),
    );
    final first = await repository.createScrap('First');
    await repository.createScrap('Second');

    await repository.updateScrap(first, 'First, edited');

    final scraps = await repository.listScraps();
    expect(scraps.map((scrap) => scrap.id), ['first', 'second']);
    expect(scraps.first.updatedAt, DateTime.utc(2026, 9, 3));
  });

  test('updateScrap preserves capture metadata and existing assets', () async {
    final firstAttachment = File(p.join(temporaryDirectory.path, 'first.png'));
    final secondAttachment = File(
      p.join(temporaryDirectory.path, 'second.jpg'),
    );
    await firstAttachment.writeAsBytes(<int>[1, 2, 3]);
    await secondAttachment.writeAsBytes(<int>[4, 5, 6]);
    final times = <DateTime>[
      DateTime(2026, 9, 4, 23, 50),
      DateTime(2026, 9, 5, 8),
    ];
    final repository = VaultRepository(
      temporaryDirectory,
      idGenerator: () => 'updated-scrap',
      now: () => times.removeAt(0),
    );
    final original = await repository.createScrap(
      'Original',
      attachmentPaths: <String>[firstAttachment.path],
    );
    final markdownFile = await repository.scrapsDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.md'))
        .cast<File>()
        .single;
    final location = ScrapLocation(
      latitude: 37.5665,
      longitude: 126.978,
      accuracyMeters: 12,
      source: 'manual',
      capturedAt: original.createdAt,
    );
    final onDisk = Scrap(
      id: original.id,
      body: original.body,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
      localDate: original.localDate,
      utcOffsetMinutes: original.utcOffsetMinutes,
      timezoneName: original.timezoneName,
      assets: original.assets,
      location: location,
    );
    await markdownFile.writeAsString(repository.codec.encode(onDisk));

    final updated = await repository.updateScrap(
      original,
      'Edited body',
      attachmentPaths: <String>[secondAttachment.path],
    );

    expect(updated.id, original.id);
    expect(updated.createdAt, original.createdAt);
    expect(updated.localDate, original.localDate);
    expect(updated.utcOffsetMinutes, original.utcOffsetMinutes);
    expect(updated.timezoneName, original.timezoneName);
    expect(updated.location, location);
    expect(updated.updatedAt, DateTime(2026, 9, 5, 8).toUtc());
    expect(updated.assets, hasLength(2));
    expect(updated.assets.first, original.assets.first);
    expect(updated.body, startsWith('Edited body\n\n![second.jpg]('));
    expect(await repository.listScraps(), <Scrap>[updated]);
    expect(
      await repository.scrapsDirectory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.md'))
          .length,
      1,
    );
  });

  test('updateScrap reports a missing source document', () async {
    final repository = VaultRepository(temporaryDirectory);
    final missing = Scrap(
      id: 'missing',
      body: 'Body',
      createdAt: DateTime.utc(2026, 9, 4),
      updatedAt: DateTime.utc(2026, 9, 4),
    );

    await expectLater(
      repository.updateScrap(missing, 'Edited'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('missing attachments fail without creating a scrap file', () async {
    final repository = VaultRepository(
      temporaryDirectory,
      idGenerator: () => 'never-written',
      now: () => DateTime.utc(2026, 9, 4),
    );

    await expectLater(
      repository.createScrap(
        'Body',
        attachmentPaths: [p.join(temporaryDirectory.path, 'missing.png')],
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await repository.scrapsDirectory.list().toList(), isEmpty);
  });
}
