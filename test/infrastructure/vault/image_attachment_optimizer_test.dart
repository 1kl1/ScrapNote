import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scrapnote/features/editor/inline_image.dart';
import 'package:scrapnote/infrastructure/vault/photo_location_reader.dart';
import '../../support/photo_fixture.dart';
import 'package:scrapnote/infrastructure/sync/sync_manifest.dart';
import 'package:scrapnote/infrastructure/sync/vault_sync_engine.dart';
import 'package:scrapnote/infrastructure/vault/image_attachment_optimizer.dart';
import 'package:scrapnote/infrastructure/vault/note_repository.dart';
import 'package:scrapnote/infrastructure/vault/oversized_image_migrator.dart';
import 'package:scrapnote/infrastructure/vault/vault_repository.dart';

class _MemoryRemote implements SyncRemote {
  @override
  String get identity => 'test-server/test-user';
  SyncManifest manifest = SyncManifest(0, {});
  final blobs = <String, Uint8List>{};

  @override
  Future<SyncManifest> readManifest() async => manifest;

  @override
  Future<void> upload(
    String digest,
    Uint8List bytes, {
    required String path,
  }) async {
    blobs[digest] = bytes;
  }

  @override
  Future<Uint8List> download(String digest) async => blobs[digest]!;

  @override
  Future<void> commit(int expectedRevision, Map<String, String> entries) async {
    manifest = SyncManifest(expectedRevision + 1, entries);
  }
}

void main() {
  late Directory sandbox;
  late File portrait;
  late List<int> sourceBytes;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scrapnote-images-');
    portrait = File(p.join(sandbox.path, 'portrait.png'));
    final image = img.Image(width: 300, height: 600);
    final random = Random(11);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(
          x,
          y,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
    }
    sourceBytes = img.encodePng(image);
    await portrait.writeAsBytes(sourceBytes);
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('compresses photos below 8 MiB with the default settings', () async {
    expect(sourceBytes.length, lessThan(8 * 1024 * 1024));

    final result = await const ImageAttachmentOptimizer().optimize(portrait);

    expect(result, isNotNull);
    expect(result!.bytes.length, lessThan(sourceBytes.length));
    expect(result.extension, '.jpg');
    final decoded = img.decodeJpg(result.bytes)!;
    expect(decoded.width, 300);
    expect(decoded.height, 600);
    expect(await portrait.readAsBytes(), sourceBytes);
  });

  test(
    'keeps a small original when compression would increase its size',
    () async {
      final source = File(p.join(sandbox.path, 'tiny.png'));
      final bytes = img.encodePng(img.Image(width: 1, height: 1));
      await source.writeAsBytes(bytes);

      expect(await const ImageAttachmentOptimizer().optimize(source), isNull);
      expect(await source.readAsBytes(), bytes);
    },
  );

  test('keeps an unreadable small image without failing the import', () async {
    final source = File(p.join(sandbox.path, 'unreadable.jpg'));
    final bytes = [1, 2, 3];
    await source.writeAsBytes(bytes);

    expect(await const ImageAttachmentOptimizer().optimize(source), isNull);
    expect(await source.readAsBytes(), bytes);
  });

  test(
    'compresses a portrait without rotating or touching the source',
    () async {
      const optimizer = ImageAttachmentOptimizer(
        triggerBytes: 1024,
        maxBytes: 12000,
        maxDimension: 120,
      );
      final result = await optimizer.optimize(portrait);

      expect(result, isNotNull);
      expect(result!.extension, '.jpg');
      expect(result.bytes.length, lessThanOrEqualTo(12000));
      final decoded = img.decodeJpg(result.bytes)!;
      expect(decoded.width, 60);
      expect(decoded.height, 120);
      expect(await portrait.readAsBytes(), sourceBytes);
    },
  );

  test('bakes EXIF rotation without rotating the saved JPEG twice', () async {
    final image = img.decodePng(Uint8List.fromList(sourceBytes))!;
    image.exif.imageIfd.orientation = 6;
    final source = File(p.join(sandbox.path, 'rotated.jpg'));
    final bytes = img.encodeJpg(image, quality: 100);
    await source.writeAsBytes(bytes);

    final result = await const ImageAttachmentOptimizer(
      maxDimension: 120,
    ).optimize(source);

    expect(result, isNotNull);
    final decoded = img.decodeJpg(result!.bytes)!;
    expect(decoded.width, 120);
    expect(decoded.height, 60);
    expect(decoded.exif.imageIfd.hasOrientation, isFalse);
    expect(await source.readAsBytes(), bytes);
  });

  test('preserves transparency when compression is needed', () async {
    final transparent = img.Image(width: 100, height: 200, numChannels: 4);
    final random = Random(17);
    for (var y = 0; y < transparent.height; y++) {
      for (var x = 0; x < transparent.width; x++) {
        transparent.setPixelRgba(
          x,
          y,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
          x < 50 ? 100 : 255,
        );
      }
    }
    final file = File(p.join(sandbox.path, 'transparent.png'));
    await file.writeAsBytes(img.encodePng(transparent));
    const optimizer = ImageAttachmentOptimizer(
      triggerBytes: 1024,
      maxBytes: 15000,
      maxDimension: 60,
    );

    final result = (await optimizer.optimize(file))!;
    expect(result.extension, '.png');
    expect(result.bytes.length, lessThanOrEqualTo(15000));
    final decoded = img.decodePng(result.bytes)!;
    expect(decoded.height, greaterThan(decoded.width));
    expect(decoded.getPixel(0, 0).aNormalized, lessThan(1));
  });

  test(
    'reports unsupported oversized formats without altering the file',
    () async {
      final source = File(p.join(sandbox.path, 'animation.gif'));
      final bytes = List<int>.filled(12001, 7);
      await source.writeAsBytes(bytes);
      const optimizer = ImageAttachmentOptimizer(
        triggerBytes: 1024,
        maxBytes: 12000,
      );

      await expectLater(
        optimizer.optimize(source),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('JPEG 또는 PNG'),
          ),
        ),
      );
      expect(await source.readAsBytes(), bytes);
    },
  );

  test(
    'compresses HEIC to an upright JPEG without altering the source',
    () async {
      final source = File(p.join(sandbox.path, 'camera.heic'));
      await source.writeAsBytes(sourceBytes);
      final compressed = Uint8List.fromList(
        img.encodeJpg(
          img.copyResize(
            img.decodePng(Uint8List.fromList(sourceBytes))!,
            height: 120,
          ),
          quality: 80,
        ),
      );
      expect(compressed.length, lessThanOrEqualTo(12000));
      expect(compressed.take(3), [0xff, 0xd8, 0xff]);
      final dimensions = <int>[];
      final optimizer = ImageAttachmentOptimizer(
        triggerBytes: 1024,
        maxBytes: 12000,
        maxDimension: 120,
        heicEncoder: (path, dimension) async {
          expect(path, source.path);
          dimensions.add(dimension);
          return compressed;
        },
      );

      final result = await optimizer.optimize(source);

      expect(dimensions, [120]);
      expect(result?.extension, '.jpg');
      final decoded = img.decodeJpg(result!.bytes)!;
      expect(decoded.width, 60);
      expect(decoded.height, 120);
      expect(await source.readAsBytes(), sourceBytes);
    },
  );

  test('retries a large HEIF at a smaller dimension', () async {
    final source = File(p.join(sandbox.path, 'camera.heif'));
    await source.writeAsBytes(sourceBytes);
    final compressed = Uint8List.fromList(
      img.encodeJpg(
        img.copyResize(
          img.decodePng(Uint8List.fromList(sourceBytes))!,
          height: 120,
        ),
        quality: 80,
      ),
    );
    final dimensions = <int>[];
    expect(compressed.length, lessThanOrEqualTo(12000));
    expect(compressed.take(3), [0xff, 0xd8, 0xff]);
    final optimizer = ImageAttachmentOptimizer(
      triggerBytes: 1024,
      maxBytes: 12000,
      maxDimension: 120,
      heicEncoder: (_, dimension) async {
        dimensions.add(dimension);
        return dimensions.length == 1
            ? Uint8List.fromList([0xff, 0xd8, 0xff, ...List.filled(12001, 0)])
            : compressed;
      },
    );

    final result = await optimizer.optimize(source);

    expect(dimensions, [120, 90]);
    expect(result?.extension, '.jpg');
    expect(result!.bytes.length, lessThanOrEqualTo(12000));
  });

  test('reports an oversized HEIC when the device cannot decode it', () async {
    final source = File(p.join(sandbox.path, 'unreadable.heic'));
    final bytes = List<int>.filled(12001, 7);
    await source.writeAsBytes(bytes);
    final optimizer = ImageAttachmentOptimizer(
      triggerBytes: 1024,
      maxBytes: 12000,
      heicEncoder: (_, _) async => null,
    );

    await expectLater(
      optimizer.optimize(source),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          contains('HEIC/HEIF'),
        ),
      ),
    );
    expect(await source.readAsBytes(), bytes);
  });

  test(
    'keeps an uploadable HEIC when native decoding is unavailable',
    () async {
      final source = File(p.join(sandbox.path, 'camera.heic'));
      await source.writeAsBytes(sourceBytes);
      final optimizer = ImageAttachmentOptimizer(
        triggerBytes: 1024,
        maxBytes: sourceBytes.length + 1,
        heicEncoder: (_, _) async => null,
      );

      expect(await optimizer.optimize(source), isNull);
      expect(await source.readAsBytes(), sourceBytes);
    },
  );

  test(
    'photo GPS and time survive compression in both the JPEG and document',
    () async {
      final source = await writePhoto(File('${sandbox.path}/gps.jpg'));
      final repository = VaultRepository(
        Directory('${sandbox.path}/vault'),
        imageOptimizer: const ImageAttachmentOptimizer(
          triggerBytes: 1,
          maxDimension: 8,
        ),
      );
      final saved = await repository.createScrap(
        'Photo',
        attachmentPaths: [source.path],
      );
      final asset = saved.assets.single;
      final stored = File(
        p.normalize(
          p.join(repository.scrapsDirectory.path, asset.relativePath),
        ),
      );
      expect(await stored.length(), lessThan(await source.length()));
      final storedLocation = await const PhotoLocationReader().read(
        stored,
        fallbackTime: saved.createdAt,
      );
      expect(storedLocation, saved.locations.single);
      expect(storedLocation!.capturedAt, DateTime.utc(2026, 9, 4, 9, 2, 3));
      await source.delete();
      expect(saved.locations.single.latitude, 37.5);
      expect((await repository.listScraps()).single.locations, saved.locations);
    },
  );

  test(
    'legacy oversized photo keeps GPS when sync replaces its image',
    () async {
      final vault = Directory('${sandbox.path}/vault');
      final source = await writePhoto(File('${sandbox.path}/gps.jpg'));
      final repository = VaultRepository(vault);
      final saved = await repository.createScrap(
        'Photo',
        attachmentPaths: [source.path],
      );
      // Mimic an old Markdown file that has not extracted photo metadata yet.
      final document = (await repository.scrapsDirectory.list().toList())
          .whereType<File>()
          .single;
      var markdown = await document.readAsString();
      markdown = markdown.replaceAll(
        RegExp(
          r'    photo_metadata_read: true\n    location:\n(?:      [^\n]*\n)+',
        ),
        '',
      );
      await document.writeAsString(markdown);
      final old = File(
        p.normalize(
          p.join(
            repository.scrapsDirectory.path,
            saved.assets.single.relativePath,
          ),
        ),
      );
      final limit = (await old.length()) - 1;
      await OversizedImageMigrator(
        vault,
        maxBytes: limit,
        maxDimension: 8,
      ).migrate();
      final loaded = (await repository.listScraps()).single;
      expect(loaded.assets.single.hash, isNot(saved.assets.single.hash));
      expect(loaded.locations.single.latitude, 37.5);
      expect(
        loaded.locations.single.capturedAt,
        saved.locations.single.capturedAt,
      );
      expect(loaded.createdAt, saved.createdAt);
      expect(loaded.updatedAt, saved.updatedAt);
    },
  );

  test('Scraps and Notes import only the optimized copy', () async {
    const optimizer = ImageAttachmentOptimizer(
      triggerBytes: 1024,
      maxBytes: 12000,
      maxDimension: 120,
    );
    final vault = Directory(p.join(sandbox.path, 'vault'));
    final scrapRepo = VaultRepository(vault, imageOptimizer: optimizer);
    final noteRepo = NoteRepository(vault, imageOptimizer: optimizer);
    final body = InlineImage.markdown(portrait.path);

    final scrap = await scrapRepo.createScrap(
      body,
      attachmentPaths: [portrait.path],
    );
    final note = await noteRepo.createNote(
      body,
      folder: '',
      attachmentPaths: [portrait.path],
    );

    expect(scrap.assets.single.hash, note.assets.single.hash);
    expect(scrap.assets.single.mimeType, 'image/jpeg');
    expect(note.assets.single.mimeType, 'image/jpeg');
    expect(scrap.body, contains('.jpg'));
    expect(note.body, contains('.jpg'));
    final asset = File(
      p.normalize(
        p.join(vault.path, 'scraps', scrap.assets.single.relativePath),
      ),
    );
    expect(await asset.length(), lessThanOrEqualTo(12000));
    expect(await portrait.readAsBytes(), sourceBytes);
  });

  test('Scraps and Notes compress small photos by default', () async {
    final vault = Directory(p.join(sandbox.path, 'vault'));
    final scrap = await VaultRepository(
      vault,
    ).createScrap('', attachmentPaths: [portrait.path]);
    final note = await NoteRepository(
      vault,
    ).createNote('', folder: '', attachmentPaths: [portrait.path]);

    expect(scrap.assets.single.hash, note.assets.single.hash);
    expect(scrap.assets.single.mimeType, 'image/jpeg');
    expect(note.assets.single.mimeType, 'image/jpeg');
    final stored = File(
      p.normalize(
        p.join(vault.path, 'scraps', scrap.assets.single.relativePath),
      ),
    );
    expect(await stored.length(), lessThan(sourceBytes.length));
    expect(await portrait.readAsBytes(), sourceBytes);
  });

  test('Scraps and Notes store compressed HEIC attachments as JPEG', () async {
    final heic = File(p.join(sandbox.path, 'portrait.heic'));
    await heic.writeAsBytes(sourceBytes);
    final compressed = Uint8List.fromList(
      img.encodeJpg(
        img.copyResize(
          img.decodePng(Uint8List.fromList(sourceBytes))!,
          height: 120,
        ),
        quality: 80,
      ),
    );
    final optimizer = ImageAttachmentOptimizer(
      triggerBytes: 1024,
      maxBytes: 12000,
      maxDimension: 120,
      heicEncoder: (_, _) async => compressed,
    );
    final vault = Directory(p.join(sandbox.path, 'vault'));
    final scrapRepo = VaultRepository(vault, imageOptimizer: optimizer);
    final noteRepo = NoteRepository(vault, imageOptimizer: optimizer);
    final body = InlineImage.markdown(heic.path);

    final scrap = await scrapRepo.createScrap(
      body,
      attachmentPaths: [heic.path],
    );
    final note = await noteRepo.createNote(
      body,
      folder: '',
      attachmentPaths: [heic.path],
    );

    expect(scrap.assets.single.hash, note.assets.single.hash);
    expect(scrap.assets.single.mimeType, 'image/jpeg');
    expect(note.assets.single.mimeType, 'image/jpeg');
    expect(scrap.body, contains('.jpg'));
    expect(note.body, contains('.jpg'));
    expect(await heic.readAsBytes(), sourceBytes);
  });

  test(
    'existing oversized photos are relinked and backed up before sync',
    () async {
      final vault = Directory(p.join(sandbox.path, 'vault'));
      // Simulate attachments saved before small photos were compressed.
      const legacyOptimizer = ImageAttachmentOptimizer(
        triggerBytes: 8 * 1024 * 1024,
      );
      final scrapRepo = VaultRepository(vault, imageOptimizer: legacyOptimizer);
      final noteRepo = NoteRepository(vault, imageOptimizer: legacyOptimizer);
      await noteRepo.createFolder('Trips');
      await noteRepo.createFolder('Seoul', parent: 'Trips');
      final body = InlineImage.markdown(portrait.path);
      final scrap = await scrapRepo.createScrap(
        body,
        attachmentPaths: [portrait.path],
      );
      final note = await noteRepo.createNote(
        body,
        folder: 'Trips/Seoul',
        attachmentPaths: [portrait.path],
      );
      final oldHash = sha256.convert(sourceBytes).toString();
      expect(scrap.assets.single.hash, oldHash);
      expect(note.assets.single.hash, oldHash);
      final oldAsset = File(
        p.normalize(
          p.join(vault.path, 'scraps', scrap.assets.single.relativePath),
        ),
      );
      expect(await oldAsset.length(), greaterThan(12000));

      final migrator = OversizedImageMigrator(
        vault,
        maxBytes: 12000,
        maxDimension: 120,
      );
      await migrator.migrate();
      final newScrap = (await scrapRepo.listScraps()).single;
      final newNote = (await noteRepo.listNotes()).single;
      expect(newScrap.assets.single.hash, isNot(oldHash));
      expect(newScrap.assets.single.hash, newNote.assets.single.hash);
      expect(newScrap.assets.single.mimeType, 'image/jpeg');
      expect(newNote.assets.single.mimeType, 'image/jpeg');
      expect(newScrap.body, contains('.jpg'));
      expect(newNote.body, contains('.jpg'));
      expect(newScrap.body, isNot(contains(oldHash)));
      expect(newNote.body, isNot(contains(oldHash)));
      expect(newScrap.createdAt, scrap.createdAt);
      expect(newNote.updatedAt, note.updatedAt);
      expect(await oldAsset.exists(), isFalse);
      final newAsset = File(
        p.normalize(
          p.join(vault.path, 'scraps', newScrap.assets.single.relativePath),
        ),
      );
      expect(await newAsset.length(), lessThanOrEqualTo(12000));
      final decoded = img.decodeJpg(await newAsset.readAsBytes())!;
      expect(decoded.height, greaterThan(decoded.width));
      expect(await portrait.readAsBytes(), sourceBytes);
      final backups = await Directory(
        p.join(vault.path, '.trash', 'image-optimization'),
      ).list(recursive: true).where((entity) => entity is File).toList();
      expect(backups, hasLength(3)); // original image and both documents
      await migrator.migrate();
      expect((await scrapRepo.listScraps()).single, newScrap);
    },
  );

  test('existing oversized HEIC is converted before sync', () async {
    final heic = File(p.join(sandbox.path, 'old.heic'));
    await heic.writeAsBytes(sourceBytes);
    final vault = Directory(p.join(sandbox.path, 'vault'));
    final scrapRepo = VaultRepository(vault);
    final scrap = await scrapRepo.createScrap(
      InlineImage.markdown(heic.path),
      attachmentPaths: [heic.path],
    );
    final oldAsset = File(
      p.normalize(
        p.join(vault.path, 'scraps', scrap.assets.single.relativePath),
      ),
    );
    final compressed = Uint8List.fromList(
      img.encodeJpg(
        img.copyResize(
          img.decodePng(Uint8List.fromList(sourceBytes))!,
          height: 120,
        ),
        quality: 80,
      ),
    );
    final migrator = OversizedImageMigrator(
      vault,
      maxBytes: 12000,
      maxDimension: 120,
      heicEncoder: (_, _) async => compressed,
    );

    await migrator.migrate();

    final updated = (await scrapRepo.listScraps()).single;
    expect(updated.assets.single.mimeType, 'image/jpeg');
    expect(updated.assets.single.hash, isNot(scrap.assets.single.hash));
    expect(updated.body, contains('.jpg'));
    expect(await oldAsset.exists(), isFalse);
    expect(await heic.readAsBytes(), sourceBytes);
  });

  test('manual sync migrates old large photos before uploading them', () async {
    final vault = Directory(p.join(sandbox.path, 'desktop'));
    final repository = VaultRepository(vault);
    final scrap = await repository.createScrap(
      InlineImage.markdown(portrait.path),
      attachmentPaths: [portrait.path],
    );
    final oldAsset = File(
      p.normalize(
        p.join(vault.path, 'scraps', scrap.assets.single.relativePath),
      ),
    );
    final remote = _MemoryRemote();
    final desktop = VaultSyncEngine(
      vault,
      remote,
      maxFileBytes: 12000,
      imageMaxDimension: 120,
    );
    await desktop.synchronize();

    expect(await oldAsset.exists(), isFalse);
    expect(
      remote.manifest.entries.keys,
      contains(
        p
            .relative(
              (await repository.scrapsDirectory.list().first).path,
              from: vault.path,
            )
            .replaceAll(r'\', '/'),
      ),
    );
    expect(remote.blobs.values.every((bytes) => bytes.length <= 12000), isTrue);
    final phoneVault = Directory(p.join(sandbox.path, 'phone'));
    final phone = VaultSyncEngine(
      phoneVault,
      remote,
      maxFileBytes: 12000,
      imageMaxDimension: 120,
    );
    await phone.synchronize();
    final received = (await VaultRepository(phoneVault).listScraps()).single;
    final receivedAsset = File(
      p.normalize(
        p.join(phoneVault.path, 'scraps', received.assets.single.relativePath),
      ),
    );
    expect(await receivedAsset.exists(), isTrue);
    expect(await receivedAsset.length(), lessThanOrEqualTo(12000));
    final decoded = img.decodeJpg(await receivedAsset.readAsBytes())!;
    expect(decoded.height, greaterThan(decoded.width));
  });
}
