/// JSON-serializable recovery data for dirty editor tabs.
class EditorRecoverySnapshot {
  EditorRecoverySnapshot({
    required this.capturedAt,
    required this.activeSessionId,
    required List<EditorRecoveryDocument> documents,
  }) : documents = List<EditorRecoveryDocument>.unmodifiable(documents);

  static const schemaVersion = 1;

  final DateTime capturedAt;
  final String? activeSessionId;
  final List<EditorRecoveryDocument> documents;

  bool get isEmpty => documents.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'active_session_id': activeSessionId,
    'documents': documents.map((document) => document.toJson()).toList(),
  };

  factory EditorRecoverySnapshot.fromJson(Object? value) {
    final map = _object(value, 'Recovery snapshot');
    final version = _integer(map['version'], 'version');
    if (version != schemaVersion) {
      throw FormatException('Unsupported recovery snapshot version $version.');
    }
    final capturedAt = DateTime.tryParse(
      _string(map['captured_at'], 'captured_at'),
    );
    if (capturedAt == null) {
      throw const FormatException('captured_at must be an ISO-8601 date.');
    }
    final activeSessionId = _nullableString(
      map['active_session_id'],
      'active_session_id',
    );
    final rawDocuments = map['documents'];
    if (rawDocuments is! List) {
      throw const FormatException('documents must be a JSON array.');
    }
    final documents = rawDocuments
        .map(EditorRecoveryDocument.fromJson)
        .toList(growable: false);
    final sessionIds = <String>{};
    for (final document in documents) {
      if (!sessionIds.add(document.sessionId)) {
        throw FormatException(
          'Duplicate recovery session ID "${document.sessionId}".',
        );
      }
    }
    if (activeSessionId != null && !sessionIds.contains(activeSessionId)) {
      throw const FormatException(
        'active_session_id must identify a recovered document.',
      );
    }
    return EditorRecoverySnapshot(
      capturedAt: capturedAt.toUtc(),
      activeSessionId: activeSessionId,
      documents: documents,
    );
  }
}

class EditorRecoveryDocument {
  EditorRecoveryDocument({
    required this.sessionId,
    required this.scrapId,
    required this.body,
    required this.savedBody,
    required List<String> pendingImagePaths,
  }) : pendingImagePaths = List<String>.unmodifiable(pendingImagePaths);

  final String sessionId;
  final String? scrapId;
  final String body;
  final String savedBody;
  final List<String> pendingImagePaths;

  Map<String, Object?> toJson() => <String, Object?>{
    'session_id': sessionId,
    'scrap_id': scrapId,
    'body': body,
    'saved_body': savedBody,
    'pending_image_paths': pendingImagePaths,
  };

  factory EditorRecoveryDocument.fromJson(Object? value) {
    final map = _object(value, 'Recovery document');
    final paths = map['pending_image_paths'];
    if (paths is! List || paths.any((path) => path is! String)) {
      throw const FormatException(
        'pending_image_paths must be an array of strings.',
      );
    }
    return EditorRecoveryDocument(
      sessionId: _string(map['session_id'], 'session_id'),
      scrapId: _nullableString(map['scrap_id'], 'scrap_id'),
      body: _string(map['body'], 'body', allowEmpty: true),
      savedBody: _string(map['saved_body'], 'saved_body', allowEmpty: true),
      pendingImagePaths: paths.cast<String>(),
    );
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$label must be a JSON object.');
  }
  return value;
}

String _string(Object? value, String key, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException(
      '$key must be a${allowEmpty ? '' : ' non-empty'} string.',
    );
  }
  return value;
}

String? _nullableString(Object? value, String key) {
  if (value == null) {
    return null;
  }
  return _string(value, key);
}

int _integer(Object? value, String key) {
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}
