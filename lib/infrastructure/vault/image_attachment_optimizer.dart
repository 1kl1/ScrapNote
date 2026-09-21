import 'dart:io';
import 'dart:isolate';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

typedef HeicEncoder = Future<Uint8List?> Function(String path, int dimension);

/// The sync server accepts at most 25 MiB per blob. Keep some headroom for
/// photos while leaving already-small attachments and their metadata intact.
class ImageAttachmentOptimizer {
  const ImageAttachmentOptimizer({
    this.triggerBytes = 8 * 1024 * 1024,
    this.maxBytes = 25 * 1024 * 1024,
    this.maxDimension = 4096,
    this.heicEncoder,
  });

  final int triggerBytes;
  final int maxBytes;
  final int maxDimension;
  final HeicEncoder? heicEncoder;

  static const _heicExtensions = {'.heic', '.heif'};

  static const _rasterExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.bmp',
    '.tif',
    '.tiff',
    '.webp',
  };

  Future<OptimizedImage?> optimize(File source) async {
    final sourceBytes = await source.length();
    if (sourceBytes <= triggerBytes && sourceBytes <= maxBytes) return null;

    final extension = p.extension(source.path).toLowerCase();
    if (!_rasterExtensions.contains(extension) &&
        !_heicExtensions.contains(extension)) {
      if (sourceBytes > maxBytes) {
        throw FileSystemException(
          '25 MiB를 초과한 이 이미지 형식은 압축할 수 없습니다. JPEG 또는 PNG로 다시 첨부해 주세요.',
          source.path,
        );
      }
      return null;
    }

    final OptimizedImage? optimized;
    if (_heicExtensions.contains(extension)) {
      optimized = await _encodeHeic(source.path);
    } else {
      optimized = await Isolate.run(
        () => _encode(source.path, maxDimension, maxBytes),
      );
    }
    if (optimized == null) {
      if (sourceBytes > maxBytes) {
        throw FileSystemException(
          _heicExtensions.contains(extension)
              ? 'HEIC/HEIF 이미지를 이 기기에서 압축하지 못했습니다. JPEG로 변환하거나 더 작은 사진을 첨부해 주세요.'
              : '25 MiB를 초과한 이미지를 읽지 못했습니다. 다시 첨부해 주세요.',
          source.path,
        );
      }
      return null;
    }
    if (optimized.bytes.length > maxBytes) {
      throw FileSystemException(
        '압축한 이미지도 25 MiB를 초과합니다. 더 작은 사진을 첨부해 주세요.',
        source.path,
      );
    }
    return optimized.bytes.length < sourceBytes ? optimized : null;
  }

  Future<OptimizedImage?> _encodeHeic(String path) async {
    final encode = heicEncoder ?? _compressHeicToJpeg;
    try {
      for (final dimension in <int>[
        maxDimension,
        (maxDimension * 0.75).round(),
        (maxDimension * 0.5).round(),
        (maxDimension * 0.35).round(),
      ]) {
        final bytes = await encode(path, dimension);
        if (bytes == null ||
            bytes.length < 3 ||
            bytes[0] != 0xff ||
            bytes[1] != 0xd8 ||
            bytes[2] != 0xff) {
          return null;
        }
        if (bytes.length <= maxBytes) return OptimizedImage(bytes, '.jpg');
      }
    } on UnsupportedError {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // HEIC decoding varies by OS and device. Keep an uploadable original;
      // an oversized original receives an actionable error from optimize().
      return null;
    }
    return null;
  }

  static Future<Uint8List?> _compressHeicToJpeg(String path, int dimension) =>
      FlutterImageCompress.compressWithFile(
        path,
        minWidth: dimension,
        minHeight: dimension,
        quality: 85,
        rotate: 0,
        autoCorrectionAngle: true,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

  static OptimizedImage? _encode(
    String filePath,
    int maxDimension,
    int maxBytes,
  ) {
    final source = img.decodeImage(File(filePath).readAsBytesSync());
    if (source == null || source.hasAnimation) return null;

    var upright = source;
    if (source.exif.imageIfd.hasOrientation &&
        source.exif.imageIfd.orientation != 1) {
      upright = img.bakeOrientation(source);
    }
    OptimizedImage? lastAttempt;
    for (final dimension in <int>[
      maxDimension,
      (maxDimension * 0.75).round(),
      (maxDimension * 0.5).round(),
      (maxDimension * 0.35).round(),
    ]) {
      final width = upright.width;
      final height = upright.height;
      final image = width >= height && width > dimension
          ? img.copyResize(
              upright,
              width: dimension,
              interpolation: img.Interpolation.linear,
            )
          : height > width && height > dimension
          ? img.copyResize(
              upright,
              height: dimension,
              interpolation: img.Interpolation.linear,
            )
          : upright;
      // Orientation is baked into pixels. Copying the original EXIF tag would
      // rotate the saved image a second time in some viewers.
      image.exif = img.ExifData();
      final transparent =
          image.hasAlpha && image.any((pixel) => pixel.aNormalized < 1);
      final bytes = transparent
          ? img.encodePng(image)
          : img.encodeJpg(image, quality: 85, chroma: img.JpegChroma.yuv420);
      lastAttempt = OptimizedImage(bytes, transparent ? '.png' : '.jpg');
      if (bytes.length <= maxBytes) {
        return lastAttempt;
      }
    }
    return lastAttempt;
  }
}

class OptimizedImage {
  const OptimizedImage(this.bytes, this.extension);

  final Uint8List bytes;
  final String extension;
}

/// Write a compressed copy without touching the picked/pasted original.
Future<void> writeOptimizedAsset(File target, Uint8List bytes) async {
  if (await target.exists()) return;
  final temporary = File(
    '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (!await target.exists()) rethrow;
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
