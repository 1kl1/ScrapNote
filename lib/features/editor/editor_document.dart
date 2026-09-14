import 'package:scrapnote/domain/scrap.dart';

/// Immutable state for one editor tab.
class EditorDocument {
  EditorDocument({
    required this.sessionId,
    required this.scrap,
    required this.body,
    required List<String> pendingImagePaths,
    String? savedBody,
  }) : savedBody = savedBody ?? scrap?.body ?? '',
       pendingImagePaths = List<String>.unmodifiable(pendingImagePaths);

  final String sessionId;
  final Scrap? scrap;
  final String body;
  final List<String> pendingImagePaths;

  /// Body at the latest successful save, used for exact dirty comparison.
  final String savedBody;

  bool get dirty => body != savedBody || pendingImagePaths.isNotEmpty;

  /// Unsaved documents intentionally remain `Untitled` until first save.
  String get displayName {
    if (scrap == null) {
      return 'Untitled';
    }
    final firstLine = _firstLineTitle(body);
    return firstLine.isEmpty ? 'Untitled' : firstLine;
  }

  EditorDocument copyWith({
    Scrap? scrap,
    bool replaceScrap = false,
    String? body,
    List<String>? pendingImagePaths,
    String? savedBody,
  }) {
    return EditorDocument(
      sessionId: sessionId,
      scrap: replaceScrap ? scrap : (scrap ?? this.scrap),
      body: body ?? this.body,
      pendingImagePaths: pendingImagePaths ?? this.pendingImagePaths,
      savedBody: savedBody ?? this.savedBody,
    );
  }

  static String _firstLineTitle(String value) {
    for (final line in value.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.replaceFirst(RegExp(r'^#{1,6}\s+'), '').trim();
      }
    }
    return '';
  }
}
