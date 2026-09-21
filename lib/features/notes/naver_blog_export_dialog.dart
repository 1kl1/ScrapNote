import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/scrapnote_tokens.dart';
import 'naver_blog_export.dart';

typedef NaverBlogClipboardWriter = Future<void> Function(String value);
typedef NaverBlogDirectoryPicker = Future<String?> Function();
typedef NaverBlogOpener = Future<bool> Function();

class NaverBlogExportDialog extends StatefulWidget {
  const NaverBlogExportDialog({
    required this.export,
    this.clipboardWriter = _writeClipboard,
    this.directoryPicker = _pickDirectory,
    this.openNaverBlog = _openNaverBlog,
    super.key,
  });

  final NaverBlogExport export;
  final NaverBlogClipboardWriter clipboardWriter;
  final NaverBlogDirectoryPicker directoryPicker;
  final NaverBlogOpener openNaverBlog;

  static Future<void> _writeClipboard(String value) =>
      Clipboard.setData(ClipboardData(text: value));

  static Future<String?> _pickDirectory() =>
      getDirectoryPath(confirmButtonText: '이 폴더에 내보내기');

  static Future<bool> _openNaverBlog() => launchUrl(
    Uri.parse('https://blog.naver.com/GoBlogWrite.naver'),
    mode: LaunchMode.externalApplication,
  );

  @override
  State<NaverBlogExportDialog> createState() => _NaverBlogExportDialogState();
}

class _NaverBlogExportDialogState extends State<NaverBlogExportDialog> {
  String? _status;
  bool _exporting = false;

  Future<void> _copy(String value, String label) async {
    await widget.clipboardWriter(value);
    if (mounted) setState(() => _status = '$label을 복사했습니다.');
  }

  Future<void> _exportFiles() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _status = null;
    });
    try {
      final directory = await widget.directoryPicker();
      if (directory == null || !mounted) return;
      final output = await widget.export.writeTo(Directory(directory));
      if (mounted) setState(() => _status = '${output.path}에 내보냈습니다.');
    } on Exception catch (error) {
      if (mounted) setState(() => _status = '내보내지 못했습니다. $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openBlog() async {
    final opened = await widget.openNaverBlog();
    if (mounted && !opened) {
      setState(() => _status = '네이버 블로그를 열지 못했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageCount = widget.export.images.length;
    final supportsFolderExport = !kIsWeb && !Platform.isIOS;
    return AlertDialog(
      backgroundColor: ScrapnoteTokens.paperRaised,
      surfaceTintColor: ScrapnoteTokens.transparent,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: ScrapnoteTokens.rule),
        borderRadius: BorderRadius.circular(ScrapnoteTokens.radiusLarge),
      ),
      title: const Text('네이버 블로그로 내보내기'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '숨은 HTML 없이 붙여넣을 수 있는 일반 글로 정리했습니다. '
                '사진은 표시된 위치에 직접 업로드해 주세요.',
                style: TextStyle(
                  color: ScrapnoteTokens.charcoalSoft,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: ScrapnoteTokens.space4),
              _CopySection(
                label: '제목',
                value: widget.export.title,
                onCopy: () => _copy(widget.export.title, '제목'),
              ),
              const SizedBox(height: ScrapnoteTokens.space3),
              _CopySection(
                label: '본문',
                value: widget.export.body,
                maxLines: 8,
                onCopy: () => _copy(widget.export.body, '본문'),
              ),
              const SizedBox(height: ScrapnoteTokens.space3),
              Row(
                children: <Widget>[
                  const Icon(
                    FLucideIcons.images,
                    size: 16,
                    color: ScrapnoteTokens.mutedInk,
                  ),
                  const SizedBox(width: ScrapnoteTokens.space2),
                  Expanded(
                    child: Text(
                      imageCount == 0
                          ? '첨부 사진 없음'
                          : '첨부 사진 $imageCount장 · 본문의 [사진 N] 순서대로 업로드',
                      style: const TextStyle(
                        color: ScrapnoteTokens.charcoalSoft,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (supportsFolderExport) ...<Widget>[
                const SizedBox(height: ScrapnoteTokens.space4),
                SizedBox(
                  height: ScrapnoteTokens.minimumHitTarget,
                  child: OutlinedButton.icon(
                    onPressed: _exporting ? null : _exportFiles,
                    icon: _exporting
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(FLucideIcons.folderDown, size: 15),
                    label: Text(
                      imageCount == 0 ? '텍스트 파일로 내보내기' : '텍스트와 사진을 폴더로 내보내기',
                    ),
                  ),
                ),
              ],
              if (_status != null) ...<Widget>[
                const SizedBox(height: ScrapnoteTokens.space3),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _status!,
                    key: const ValueKey<String>('naver-export-status'),
                    style: const TextStyle(
                      color: ScrapnoteTokens.charcoalSoft,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton.icon(
          onPressed: _openBlog,
          icon: const Icon(FLucideIcons.externalLink, size: 15),
          label: const Text('네이버 블로그 열기'),
        ),
      ],
    );
  }
}

class _CopySection extends StatelessWidget {
  const _CopySection({
    required this.label,
    required this.value,
    required this.onCopy,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final int maxLines;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: ScrapnoteTokens.paperSunken,
      border: Border.all(color: ScrapnoteTokens.rule),
      borderRadius: BorderRadius.circular(ScrapnoteTokens.radius),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: ScrapnoteTokens.mutedInk,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value.isEmpty ? '(내용 없음)' : value,
                  maxLines: maxLines,
                  style: const TextStyle(
                    color: ScrapnoteTokens.charcoal,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: '$label 복사',
            child: IconButton(
              onPressed: onCopy,
              icon: const Icon(FLucideIcons.copy, size: 15),
            ),
          ),
        ],
      ),
    ),
  );
}
