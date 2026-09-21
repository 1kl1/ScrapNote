import 'dart:async';
import 'dart:io';

import '../../features/editor/inline_image.dart';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/infrastructure/vault/front_matter_codec.dart';
import 'package:uuid/uuid.dart';

import 'image_attachment_optimizer.dart';

typedef ScrapIdGenerator = String Function();
typedef VaultClock = DateTime Function();

/// File-system source of truth for scraps and their content-addressed assets.
class VaultRepository {
  VaultRepository(
    Object root, {
    ScrapFileCodec? codec,
    ScrapIdGenerator? idGenerator,
    VaultClock? now,
    this._imageOptimizer = const ImageAttachmentOptimizer(),
  }) : root = switch (root) {
         Directory directory => directory,
         String path => Directory(path),
         _ => throw ArgumentError.value(
           root,
           'root',
           'Must be a Directory or path.',
         ),
       },
       codec = codec ?? const ScrapFileCodec(),
       _idGenerator = idGenerator ?? const Uuid().v7,
       _now = now ?? DateTime.now;

  final Directory root;
  final ScrapFileCodec codec;
  final ScrapIdGenerator _idGenerator;
  final VaultClock _now;
  final ImageAttachmentOptimizer _imageOptimizer;

  Directory get scrapsDirectory => Directory(p.join(root.path, 'scraps'));
  Directory get assetsDirectory =>
      Directory(p.join(root.path, 'assets', 'sha256'));

  Future<void> initialize() async {
    await root.create(recursive: true);
    await scrapsDirectory.create(recursive: true);
    await assetsDirectory.create(recursive: true);
  }

  Future<List<Scrap>> listScraps() async {
    await initialize();
    final scraps = <Scrap>[];

    await for (final entity in scrapsDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.md') {
        continue;
      }

      try {
        scraps.add(codec.decode(await entity.readAsString()));
      } on FormatException catch (error) {
        throw FormatException(
          'Could not read ${entity.path}: ${error.message}',
        );
      }
    }

    scraps.sort((left, right) {
      final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
      if (byUpdatedAt != 0) {
        return byUpdatedAt;
      }
      final byCreatedAt = right.createdAt.compareTo(left.createdAt);
      if (byCreatedAt != 0) {
        return byCreatedAt;
      }
      return right.id.compareTo(left.id);
    });
    return List<Scrap>.unmodifiable(scraps);
  }

  Future<Scrap> createScrap(
    String body, {
    Iterable<String> attachmentPaths = const <String>[],
    ScrapLocation? location,
  }) async {
    await initialize();

    final assets = <ScrapAsset>[];
    final seenHashes = <String>{};
    for (final attachmentPath in attachmentPaths) {
      final asset = await _importAsset(File(attachmentPath));
      body = InlineImage.persist(
        body,
        attachmentPath,
        asset.relativePath,
        asset.originalName,
      );
      if (seenHashes.add(asset.hash)) {
        assets.add(asset);
      }
    }

    final localNow = _now();
    final createdAt = localNow.toUtc();
    final id = _idGenerator().trim();
    if (id.isEmpty) {
      throw StateError('The scrap ID generator returned an empty ID.');
    }

    final scrap = Scrap(
      id: id,
      body: body,
      createdAt: createdAt,
      updatedAt: createdAt,
      localDate: _localDate(localNow),
      utcOffsetMinutes: localNow.timeZoneOffset.inMinutes,
      timezoneName: localNow.timeZoneName.trim().isEmpty
          ? (localNow.isUtc ? 'UTC' : 'local')
          : localNow.timeZoneName,
      assets: List<ScrapAsset>.unmodifiable(assets),
      location: location,
    );

    final target = File(
      p.join(scrapsDirectory.path, _scrapFileName(createdAt, id)),
    );
    if (await target.exists()) {
      throw StateError('A scrap file already exists at ${target.path}.');
    }
    await _atomicWrite(target, codec.encode(scrap));
    return scrap;
  }

  /// Rewrites an existing scrap while retaining capture-time metadata.
  ///
  /// [existing] identifies the document. The current on-disk document is read
  /// before writing so location, assets, and capture-time fields changed by an
  /// external editor are not replaced with stale in-memory values.
  Future<Scrap> updateScrap(
    Scrap existing,
    String body, {
    Iterable<String> attachmentPaths = const <String>[],
  }) async {
    await initialize();

    final record = await _findScrap(existing.id);
    if (record == null) {
      throw FileSystemException(
        'The scrap no longer exists in this Vault.',
        existing.id,
      );
    }

    final persisted = record.scrap;
    final assets = <ScrapAsset>[...persisted.assets];
    final knownHashes = assets.map((asset) => asset.hash).toSet();

    for (final attachmentPath in attachmentPaths) {
      final asset = await _importAsset(
        File(attachmentPath),
        relativeFrom: record.file.parent,
      );
      body = InlineImage.persist(
        body,
        attachmentPath,
        asset.relativePath,
        asset.originalName,
      );
      if (knownHashes.add(asset.hash)) {
        assets.add(asset);
      }
    }

    final updated = Scrap(
      id: persisted.id,
      body: body,
      createdAt: persisted.createdAt,
      updatedAt: _now().toUtc(),
      localDate: persisted.localDate,
      utcOffsetMinutes: persisted.utcOffsetMinutes,
      timezoneName: persisted.timezoneName,
      assets: List<ScrapAsset>.unmodifiable(assets),
      location: persisted.location,
    );
    await _atomicWrite(record.file, codec.encode(updated));
    return updated;
  }

  /// Replaces the persisted location without changing the Scrap body or assets.
  Future<Scrap> updateScrapLocation(
    Scrap existing,
    ScrapLocation location,
  ) async {
    if (!location.latitude.isFinite ||
        location.latitude < -90 ||
        location.latitude > 90 ||
        !location.longitude.isFinite ||
        location.longitude < -180 ||
        location.longitude > 180 ||
        !location.accuracyMeters.isFinite ||
        location.accuracyMeters < 0) {
      throw const FormatException('위도, 경도 또는 정확도 값이 올바르지 않습니다.');
    }

    await initialize();
    final record = await _findScrap(existing.id);
    if (record == null) {
      throw FileSystemException(
        'The scrap no longer exists in this Vault.',
        existing.id,
      );
    }

    final persisted = record.scrap;
    final updated = Scrap(
      id: persisted.id,
      body: persisted.body,
      createdAt: persisted.createdAt,
      updatedAt: _now().toUtc(),
      localDate: persisted.localDate,
      utcOffsetMinutes: persisted.utcOffsetMinutes,
      timezoneName: persisted.timezoneName,
      assets: persisted.assets,
      location: location,
    );
    await _atomicWrite(record.file, codec.encode(updated));
    return updated;
  }

  /// Move only the document to Vault trash. Shared assets remain available to Notes.
  Future<void> deleteScrap(String id) async {
    final record = await _findScrap(id);
    if (record == null) return;
    final trash = Directory(p.join(root.path, '.trash', 'scraps'));
    await trash.create(recursive: true);
    await record.file.rename(
      p.join(
        trash.path,
        '${DateTime.now().microsecondsSinceEpoch}-${p.basename(record.file.path)}',
      ),
    );
  }

  Future<_ScrapFileRecord?> _findScrap(String id) async {
    _ScrapFileRecord? match;
    await for (final entity in scrapsDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.md') {
        continue;
      }
      final scrap = codec.decode(await entity.readAsString());
      if (scrap.id != id) {
        continue;
      }
      if (match != null) {
        throw StateError('Multiple Scrap files use the ID "$id".');
      }
      match = _ScrapFileRecord(entity, scrap);
    }
    return match;
  }

  Future<ScrapAsset> _importAsset(
    File source, {
    Directory? relativeFrom,
  }) async {
    if (!await source.exists()) {
      throw FileSystemException('Attachment does not exist.', source.path);
    }
    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Attachment is not a regular file.',
        source.path,
      );
    }

    final optimized = await _imageOptimizer.optimize(source);
    final hash = optimized == null
        ? (await sha256.bind(source.openRead()).first).toString()
        : sha256.convert(optimized.bytes).toString();
    final bucket = Directory(
      p.join(assetsDirectory.path, hash.substring(0, 2)),
    );
    await bucket.create(recursive: true);

    final existing = await _findAssetWithHash(bucket, hash);
    final stored =
        existing ??
        File(
          p.join(
            bucket.path,
            '$hash${optimized?.extension ?? _extension(source.path)}',
          ),
        );
    if (existing == null) {
      if (optimized case final compressed?) {
        await writeOptimizedAsset(stored, compressed.bytes);
      } else {
        await _atomicCopy(source, stored, expectedHash: hash);
      }
    }

    return ScrapAsset(
      hash: hash,
      relativePath: _toPosixPath(
        p.relative(stored.path, from: (relativeFrom ?? scrapsDirectory).path),
      ),
      originalName: p.basename(source.path),
      mimeType: _mimeType(stored.path),
    );
  }

  static Future<File?> _findAssetWithHash(Directory bucket, String hash) async {
    await for (final entity in bucket.list(followLinks: false)) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name == hash || name.startsWith('$hash.')) {
          return entity;
        }
      }
    }
    return null;
  }

  static Future<void> _atomicCopy(
    File source,
    File target, {
    required String expectedHash,
  }) async {
    final temporary = File(
      p.join(
        target.parent.path,
        '.${p.basename(target.path)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );

    try {
      final sink = temporary.openWrite(mode: FileMode.writeOnly);
      try {
        await sink.addStream(source.openRead());
        await sink.flush();
      } finally {
        await sink.close();
      }

      final copiedHash = (await sha256.bind(temporary.openRead()).first)
          .toString();
      if (copiedHash != expectedHash) {
        throw FileSystemException(
          'Attachment changed while it was being imported.',
          source.path,
        );
      }

      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        // A concurrent import of the same content may have won the race.
        if (!await target.exists()) {
          rethrow;
        }
      }
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  static Future<void> _atomicWrite(File target, String contents) async {
    final temporary = File(
      p.join(
        target.parent.path,
        '.${p.basename(target.path)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  static String _scrapFileName(DateTime date, String id) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stamp =
        '${date.year.toString().padLeft(4, '0')}'
        '${two(date.month)}${two(date.day)}-'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}'
        '${three(date.millisecond)}';
    return '$stamp--$safeId.md';
  }

  static String _localDate(DateTime value) {
    String two(int component) => component.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)}';
  }

  static String _extension(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension)) {
      return '';
    }
    return extension == '.jpeg' ? '.jpg' : extension;
  }

  static String _mimeType(String filePath) {
    return switch (p.extension(filePath).toLowerCase()) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.heic' => 'image/heic',
      '.heif' => 'image/heif',
      '.tif' || '.tiff' => 'image/tiff',
      '.bmp' => 'image/bmp',
      '.svg' => 'image/svg+xml',
      _ => 'application/octet-stream',
    };
  }

  static String _toPosixPath(String value) => value.replaceAll(r'\', '/');
}

class _ScrapFileRecord {
  const _ScrapFileRecord(this.file, this.scrap);

  final File file;
  final Scrap scrap;
}
