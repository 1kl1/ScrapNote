import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/scrap.dart';
import '../../features/editor/inline_image.dart';
import 'front_matter_codec.dart';
import 'image_attachment_optimizer.dart';
import 'note_file_codec.dart';

/// Repairs older, over-limit Vault attachments before a user-requested sync.
/// Originals and changed documents remain recoverable in Vault trash.
class OversizedImageMigrator {
  OversizedImageMigrator(
    this.root, {
    this.maxBytes = 25 * 1024 * 1024,
    this.maxDimension = 4096,
    this.heicEncoder,
  });

  final Directory root;
  final int maxBytes;
  final int maxDimension;
  final HeicEncoder? heicEncoder;

  Directory get _assets => Directory(p.join(root.path, 'assets', 'sha256'));

  Future<void> migrate() async {
    if (!await _assets.exists()) return;
    await for (final entity in _assets.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || await entity.length() <= maxBytes) continue;
      final relative = p.relative(entity.path, from: _assets.path);
      if (!RegExp(
        r'^[a-f0-9]{2}/[a-f0-9]{64}\.[a-z0-9]+$',
      ).hasMatch(relative.replaceAll(r'\', '/'))) {
        throw FileSystemException(
          '25 MiB를 초과한 수동 파일은 자동 압축할 수 없습니다.',
          entity.path,
        );
      }
      await _migrateOne(entity);
    }
  }

  Future<void> _migrateOne(File original) async {
    final optimizer = ImageAttachmentOptimizer(
      triggerBytes: maxBytes,
      maxBytes: maxBytes,
      maxDimension: maxDimension,
      heicEncoder: heicEncoder,
    );
    final result = await optimizer.optimize(original);
    if (result == null) {
      throw FileSystemException('큰 이미지를 압축하지 못했습니다.', original.path);
    }
    final hash = sha256.convert(result.bytes).toString();
    final replacement = File(
      p.join(_assets.path, hash.substring(0, 2), '$hash${result.extension}'),
    );
    await replacement.parent.create(recursive: true);
    if (await FileSystemEntity.type(replacement.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('이미지 저장 위치가 바로가기입니다.', replacement.path);
    }
    if (await replacement.exists()) {
      final digest = (await sha256.bind(replacement.openRead()).first)
          .toString();
      if (digest != hash) {
        throw FileSystemException('기존 이미지 파일의 내용이 변경되었습니다.', replacement.path);
      }
    } else {
      await writeOptimizedAsset(replacement, result.bytes);
    }

    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final backupRoot = Directory(
      p.join(root.path, '.trash', 'image-optimization', stamp),
    );
    for (final name in ['.trash', '.trash/image-optimization']) {
      final directory = Directory(p.join(root.path, name));
      if (await FileSystemEntity.type(directory.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException(
          '이미지 복구 폴더가 바로가기여서 안전하게 압축할 수 없습니다.',
          directory.path,
        );
      }
    }
    final changes = await _documentChanges(original, replacement, hash);
    for (final entry in changes.entries) {
      final document = entry.key;
      final backup = File(
        p.join(backupRoot.path, p.relative(document.path, from: root.path)),
      );
      await backup.parent.create(recursive: true);
      await document.copy(backup.path);
      await _atomicWrite(document, entry.value);
    }
    final originalBackup = File(
      p.join(backupRoot.path, p.relative(original.path, from: root.path)),
    );
    await originalBackup.parent.create(recursive: true);
    await original.rename(originalBackup.path);
  }

  Future<Map<File, String>> _documentChanges(
    File original,
    File replacement,
    String newHash,
  ) async {
    final changes = <File, String>{};
    for (final folder in ['scraps', 'notes']) {
      final directory = Directory(p.join(root.path, folder));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || p.extension(entity.path) != '.md') continue;
        final current = await entity.readAsString();
        if (!current.contains(p.basename(original.path))) continue;
        // Only parse/re-encode documents that actually reference this asset.
        // The codec preserves capture and modified timestamps.
        if (folder == 'scraps') {
          final codec = const ScrapFileCodec();
          final scrap = codec.decode(current);
          final updatedBody = _relinkBody(
            scrap.body,
            entity,
            original,
            replacement,
          );
          final updatedAssets = [
            for (final asset in scrap.assets)
              _relinkAsset(asset, entity, original, replacement, newHash),
          ];
          if (updatedBody != scrap.body ||
              !_sameAssets(updatedAssets, scrap.assets)) {
            changes[entity] = codec.encode(
              Scrap(
                id: scrap.id,
                body: updatedBody,
                createdAt: scrap.createdAt,
                updatedAt: scrap.updatedAt,
                localDate: scrap.localDate,
                utcOffsetMinutes: scrap.utcOffsetMinutes,
                timezoneName: scrap.timezoneName,
                assets: updatedAssets,
                location: scrap.location,
              ),
            );
          }
        } else {
          final codec = const NoteFileCodec();
          final note = codec.decode(current, filePath: entity.path);
          final updatedBody = _relinkBody(
            note.body,
            entity,
            original,
            replacement,
          );
          final updatedAssets = [
            for (final asset in note.assets)
              _relinkAsset(asset, entity, original, replacement, newHash),
          ];
          if (updatedBody != note.body ||
              !_sameAssets(updatedAssets, note.assets)) {
            changes[entity] = codec.encode(
              note.copyWith(body: updatedBody, assets: updatedAssets),
            );
          }
        }
        // A different kind of Markdown link cannot be updated safely.
        if ((changes[entity] ?? current).contains(p.basename(original.path))) {
          throw FileSystemException(
            '큰 이미지의 문서 링크를 확인하지 못했습니다. 수동으로 다시 첨부해 주세요.',
            entity.path,
          );
        }
      }
    }
    return changes;
  }

  static bool _sameAssets(List<ScrapAsset> a, List<ScrapAsset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static ScrapAsset _relinkAsset(
    ScrapAsset asset,
    File document,
    File original,
    File replacement,
    String newHash,
  ) {
    final oldPath = p.normalize(
      p.join(document.parent.path, asset.relativePath),
    );
    if (oldPath != p.normalize(original.path)) return asset;
    return ScrapAsset(
      hash: newHash,
      relativePath: p
          .relative(replacement.path, from: document.parent.path)
          .replaceAll(r'\', '/'),
      originalName: asset.originalName,
      mimeType: replacement.path.endsWith('.jpg') ? 'image/jpeg' : 'image/png',
    );
  }

  static String _relinkBody(
    String body,
    File document,
    File original,
    File replacement,
  ) => body.replaceAllMapped(InlineImage.pattern, (match) {
    final value = match.group(2)!;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.hasScheme && uri.scheme != 'file')) {
      return match.group(0)!;
    }
    final oldPath = uri.hasScheme
        ? uri.toFilePath()
        : Uri.directory(document.parent.path).resolveUri(uri).toFilePath();
    if (p.normalize(oldPath) != p.normalize(original.path)) {
      return match.group(0)!;
    }
    final relative = p
        .relative(replacement.path, from: document.parent.path)
        .replaceAll(r'\', '/');
    return match
        .group(0)!
        .replaceFirst(value, InlineImage.encodePath(relative));
  });

  static Future<void> _atomicWrite(File file, String contents) async {
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      if (Platform.isWindows && await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
