// Hallmark · component: document renderer · genre: modern-minimal
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/design/scrapnote_tokens.dart';
import 'inline_image.dart';

/// Renders Markdown while resolving relative image links from a local folder.
class LocalMarkdownView extends StatelessWidget {
  const LocalMarkdownView({
    required this.data,
    required this.imageDirectory,
    this.padding = EdgeInsets.zero,
    this.selectable = true,
    super.key,
  });

  final String data;
  final String imageDirectory;
  final EdgeInsets padding;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final directoryUri = Uri.directory(imageDirectory).toString();
    Widget image(Uri uri, String? title, String? alt) {
      final resolved = uri.hasScheme
          ? uri
          : Uri.parse(directoryUri).resolveUri(uri);
      return _DocumentImage(
        label: alt,
        alignment: title,
        child: _resolvedImage(resolved),
      );
    }

    Widget markdown(String source) => MarkdownBody(
      data: source,
      selectable: selectable,
      imageDirectory: directoryUri,
      styleSheet: _styleSheet(context),
      imageBuilder: image,
    );

    final rows = InlineImageRow.pattern.allMatches(data).toList();
    if (rows.isEmpty) return Padding(padding: padding, child: markdown(data));
    final children = <Widget>[];
    var offset = 0;
    for (final row in rows) {
      final before = data.substring(offset, row.start);
      if (before.trim().isNotEmpty) children.add(markdown(before));
      children.add(
        SizedBox(
          height: 230,
          child: _PreviewImageStrip(
            images: <Widget>[
              for (final item in InlineImageRow.items(row.group(0)!))
                _previewRowImage(item, directoryUri),
            ],
          ),
        ),
      );
      offset = row.end;
    }
    final after = data.substring(offset);
    if (after.trim().isNotEmpty) children.add(markdown(after));
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  static Widget _resolvedImage(Uri uri) {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(
        uri.toString(),
        fit: BoxFit.contain,
        errorBuilder: _imageError,
      );
    }
    return Image.file(
      File.fromUri(uri),
      fit: BoxFit.contain,
      errorBuilder: _imageError,
    );
  }

  static Widget _previewRowImage(String markdown, String directoryUri) {
    final match = InlineImage.pattern.firstMatch(markdown)!;
    final uri = Uri.parse(directoryUri).resolve(match.group(2)!);
    final label = match.group(1)!.replaceAll(r'\[', '[').replaceAll(r'\]', ']');
    return SizedBox(
      width: 260,
      child: Semantics(
        image: true,
        label: label.isEmpty ? 'Document image' : label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ScrapnoteTokens.paperSunken,
            border: Border.all(color: ScrapnoteTokens.rule),
            borderRadius: BorderRadius.circular(ScrapnoteTokens.radius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(ScrapnoteTokens.space2),
            child: ClipRect(child: _resolvedImage(uri)),
          ),
        ),
      ),
    );
  }

  static Widget _imageError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const SizedBox(
      height: 80,
      child: Center(
        child: Text(
          'Image unavailable',
          style: TextStyle(color: ScrapnoteTokens.mutedInk, fontSize: 12),
        ),
      ),
    );
  }

  static MarkdownStyleSheet _styleSheet(BuildContext context) {
    const body = TextStyle(
      color: ScrapnoteTokens.charcoal,
      fontSize: 15,
      height: 1.6,
    );
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      h1: body.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3),
      h2: body.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      h3: body.copyWith(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4),
      code: body.copyWith(
        fontFamily: 'monospace',
        fontSize: 13,
        backgroundColor: ScrapnoteTokens.paperSunken,
      ),
      blockquote: body.copyWith(color: ScrapnoteTokens.charcoalSoft),
      blockquoteDecoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: ScrapnoteTokens.ruleStrong, width: 2),
        ),
      ),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ScrapnoteTokens.rule)),
      ),
      a: body.copyWith(
        color: ScrapnoteTokens.signalOrange,
        decoration: TextDecoration.underline,
      ),
      listBullet: body,
      tableBody: body.copyWith(fontSize: 13),
      tableHead: body.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
      blockSpacing: ScrapnoteTokens.space3,
    );
  }
}

class _PreviewImageStrip extends StatefulWidget {
  const _PreviewImageStrip({required this.images});

  final List<Widget> images;

  @override
  State<_PreviewImageStrip> createState() => _PreviewImageStripState();
}

class _PreviewImageStripState extends State<_PreviewImageStrip> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: ListView.separated(
      key: const ValueKey<String>('preview-horizontal-image-row'),
      controller: _controller,
      scrollDirection: Axis.horizontal,
      itemCount: widget.images.length,
      separatorBuilder: (_, _) => const SizedBox(width: ScrapnoteTokens.space3),
      itemBuilder: (_, index) => widget.images[index],
    ),
  );
}

class _DocumentImage extends StatelessWidget {
  const _DocumentImage({
    required this.label,
    required this.child,
    this.alignment,
  });

  final String? label;
  final String? alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: label?.trim().isEmpty ?? true ? 'Document image' : label,
      child: Align(
        alignment: switch (alignment?.split(':').first) {
          'left' => Alignment.centerLeft,
          'right' => Alignment.centerRight,
          _ => Alignment.center,
        },
        child: FractionallySizedBox(
          widthFactor:
              (int.tryParse(alignment?.split(':').last ?? '') ?? 100) / 100,
          child: ClipRect(child: child),
        ),
      ),
    );
  }
}
