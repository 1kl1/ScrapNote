import 'dart:io';

import 'package:path/path.dart' as path;

import '../editor/inline_image.dart';
import '../editor/scrap_embed.dart';

class NaverBlogExportImage {
  const NaverBlogExportImage({
    required this.index,
    required this.label,
    required this.source,
    required this.localPath,
  });

  final int index;
  final String label;
  final String source;
  final String? localPath;

  String get exportName {
    final sourceName = localPath == null ? label : path.basename(localPath!);
    final safeName = NaverBlogExport.safeFileName(
      sourceName,
      fallback: 'image',
    );
    return '${index.toString().padLeft(2, '0')}-$safeName';
  }
}

/// A plain-text package tailored for Naver Blog's SmartEditor.
///
/// Naver does not expose a public post-writing API. Keeping the export as plain
/// text avoids carrying hidden HTML into SmartEditor, while numbered image
/// markers preserve where local images belong in the post.
class NaverBlogExport {
  const NaverBlogExport({
    required this.title,
    required this.body,
    required this.images,
  });

  final String title;
  final String body;
  final List<NaverBlogExportImage> images;

  static NaverBlogExport fromMarkdown({
    required String title,
    required String markdown,
    required String imageDirectory,
  }) {
    final images = <NaverBlogExportImage>[];
    var text = markdown.replaceAllMapped(
      ScrapEmbed.pattern,
      (match) => ScrapEmbed.content(match.group(0)!),
    );
    text = text.replaceAllMapped(InlineImage.pattern, (match) {
      final source = match.group(2)!;
      final label = _unescape(match.group(1)!).trim();
      final index = images.length + 1;
      images.add(
        NaverBlogExportImage(
          index: index,
          label: label.isEmpty ? '사진 $index' : label,
          source: source,
          localPath: _localImagePath(source, imageDirectory),
        ),
      );
      final markerLabel = label.isEmpty ? '' : ' · $label';
      return '\n[사진 $index$markerLabel]\n';
    });

    text = text
        .replaceAll(RegExp(r'<!--[^>]*-->'), '')
        .replaceAll(RegExp(r'^\s*```[^\n]*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
        .replaceAllMapped(
          RegExp(r'^(\s*)[-*+]\s+\[ \]\s+', multiLine: true),
          (match) => '${match.group(1)}☐ ',
        )
        .replaceAllMapped(
          RegExp(r'^(\s*)[-*+]\s+\[[xX]\]\s+', multiLine: true),
          (match) => '${match.group(1)}☑ ',
        )
        .replaceAllMapped(
          RegExp(r'^(\s*)[-*+]\s+', multiLine: true),
          (match) => '${match.group(1)}• ',
        )
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+)(?:\s+"[^"]*")?\)'),
          (match) => '${match.group(1)}\n${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\(([^\s)]+)(?:\s+"[^"]*")?\)'),
          (match) => match.group(1)!,
        )
        .replaceAllMapped(
          RegExp(r'(\*\*|__)(.*?)\1'),
          (match) => match.group(2)!,
        )
        .replaceAllMapped(
          RegExp(r'(?<!\*)\*([^*\n]+)\*(?!\*)'),
          (match) => match.group(1)!,
        )
        .replaceAllMapped(
          RegExp(r'(?<!_)_([^_\n]+)_(?!_)'),
          (match) => match.group(1)!,
        )
        .replaceAllMapped(RegExp(r'~~(.*?)~~'), (match) => match.group(1)!)
        .replaceAllMapped(RegExp(r'`([^`\n]+)`'), (match) => match.group(1)!)
        .replaceAll(
          RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$', multiLine: true),
          '────────',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    text = _unescape(text)
        .replaceAll(RegExp(r'[ \t]+$', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return NaverBlogExport(
      title: title.trim().isEmpty ? '제목 없음' : title.trim(),
      body: text,
      images: List<NaverBlogExportImage>.unmodifiable(images),
    );
  }

  Future<Directory> writeTo(Directory parent) async {
    final baseName = '${safeFileName(title, fallback: 'naver-blog')}_naver';
    var output = Directory(path.join(parent.path, baseName));
    var suffix = 2;
    while (await output.exists()) {
      output = Directory(path.join(parent.path, '$baseName ($suffix)'));
      suffix += 1;
    }
    await output.create(recursive: true);
    await File(path.join(output.path, '제목.txt')).writeAsString('$title\n');
    await File(path.join(output.path, '본문.txt')).writeAsString('$body\n');

    final missing = <NaverBlogExportImage>[];
    if (images.isNotEmpty) {
      final imageOutput = Directory(path.join(output.path, 'images'));
      await imageOutput.create();
      for (final image in images) {
        final localPath = image.localPath;
        if (localPath == null || !await File(localPath).exists()) {
          missing.add(image);
          continue;
        }
        await File(
          localPath,
        ).copy(path.join(imageOutput.path, image.exportName));
      }
    }

    final guide = StringBuffer()
      ..writeln('네이버 블로그 작성 순서')
      ..writeln()
      ..writeln('1. 제목.txt의 내용을 제목 칸에 붙여 넣습니다.')
      ..writeln('2. 본문.txt의 내용을 본문 칸에 붙여 넣습니다.')
      ..writeln('3. 본문의 [사진 N] 위치에 images 폴더의 같은 번호 사진을 업로드합니다.')
      ..writeln('4. 네이버에서 미리보기와 공개 설정을 확인한 뒤 직접 발행합니다.');
    if (missing.isNotEmpty) {
      guide
        ..writeln()
        ..writeln('찾지 못한 이미지')
        ..writeAll(
          missing.map((image) => '- 사진 ${image.index}: ${image.source}\n'),
        );
    }
    await File(
      path.join(output.path, '작성 안내.txt'),
    ).writeAsString(guide.toString());
    return output;
  }

  static String safeFileName(String value, {required String fallback}) {
    final sanitized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (sanitized.isEmpty) return fallback;
    return sanitized.length > 80
        ? sanitized.substring(0, 80).trim()
        : sanitized;
  }

  static String? _localImagePath(String source, String imageDirectory) {
    final uri = Uri.tryParse(source);
    if (uri == null) return null;
    if (uri.scheme == 'file') return path.normalize(uri.toFilePath());
    if (uri.hasScheme) return null;
    return path.normalize(
      path.join(imageDirectory, Uri.decodeComponent(uri.path)),
    );
  }

  static String _unescape(String value) => value.replaceAllMapped(
    RegExp(r'\\([\\`*{}\[\]()#+\-.!_>])'),
    (match) => match.group(1)!,
  );
}
