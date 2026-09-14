// Hallmark · component: document renderer · genre: modern-minimal
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/design/scrapnote_tokens.dart';

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
    return MarkdownBody(
      data: data,
      selectable: selectable,
      imageDirectory: directoryUri,
      styleSheet: _styleSheet(context),
      imageBuilder: (uri, title, alt) {
        final resolved = uri.hasScheme
            ? uri
            : Uri.parse(directoryUri).resolveUri(uri);
        if (resolved.scheme == 'http' || resolved.scheme == 'https') {
          return _DocumentImage(
            label: alt,
            alignment: title,
            child: Image.network(
              resolved.toString(),
              fit: BoxFit.contain,
              errorBuilder: _imageError,
            ),
          );
        }
        return _DocumentImage(
          label: alt,
          alignment: title,
          child: Image.file(
            File.fromUri(resolved),
            fit: BoxFit.contain,
            errorBuilder: _imageError,
          ),
        );
      },
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
        alignment: switch (alignment) {
          'left' => Alignment.centerLeft,
          'right' => Alignment.centerRight,
          _ => Alignment.center,
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420, maxWidth: 720),
          child: ClipRect(child: child),
        ),
      ),
    );
  }
}
