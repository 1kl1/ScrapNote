import 'package:flutter/foundation.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/editor/editor_document.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_snapshot.dart';
import 'package:uuid/uuid.dart';

typedef EditorSessionIdGenerator = String Function();
typedef EditorClock = DateTime Function();

/// Owns open editor tabs independently from their visual presentation.
class EditorSessionController extends ChangeNotifier {
  EditorSessionController({
    EditorSessionIdGenerator? sessionIdGenerator,
    EditorClock? now,
  }) : _sessionIdGenerator = sessionIdGenerator ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final EditorSessionIdGenerator _sessionIdGenerator;
  final EditorClock _now;

  List<EditorDocument> _documents = const <EditorDocument>[];
  String? _activeSessionId;

  List<EditorDocument> get documents =>
      List<EditorDocument>.unmodifiable(_documents);
  String? get activeSessionId => _activeSessionId;
  EditorDocument? get activeDocument => _documentFor(_activeSessionId);
  bool get hasDirtyDocuments => _documents.any((document) => document.dirty);

  /// Refresh saved tabs after a sync; never overwrite an unsaved draft.
  void refreshSavedDocuments(List<Scrap> scraps) {
    final byId = {for (final scrap in scraps) scrap.id: scrap};
    _documents = [
      for (final document in _documents)
        if (document.dirty || document.scrap == null)
          document
        else if (byId[document.scrap!.id] case final saved?)
          document.copyWith(
            scrap: saved,
            body: saved.body,
            savedBody: saved.body,
          ),
    ];
    if (_documentFor(_activeSessionId) == null) {
      _activeSessionId = _documents.lastOrNull?.sessionId;
    }
    notifyListeners();
  }

  EditorDocument newDocument() {
    final document = EditorDocument(
      sessionId: _newSessionId(),
      scrap: null,
      body: '',
      pendingImagePaths: const <String>[],
    );
    _documents = <EditorDocument>[..._documents, document];
    _activeSessionId = document.sessionId;
    notifyListeners();
    return document;
  }

  EditorDocument openScrap(Scrap scrap) {
    for (final document in _documents) {
      if (document.scrap?.id == scrap.id) {
        if (_activeSessionId != document.sessionId) {
          _activeSessionId = document.sessionId;
          notifyListeners();
        }
        return document;
      }
    }

    final document = EditorDocument(
      sessionId: _newSessionId(),
      scrap: scrap,
      body: scrap.body,
      savedBody: scrap.body,
      pendingImagePaths: const <String>[],
    );
    _documents = <EditorDocument>[..._documents, document];
    _activeSessionId = document.sessionId;
    notifyListeners();
    return document;
  }

  bool activateDocument(String sessionId) {
    if (_activeSessionId == sessionId) {
      return true;
    }
    if (_documentFor(sessionId) == null) {
      return false;
    }
    _activeSessionId = sessionId;
    notifyListeners();
    return true;
  }

  bool updateActiveBody(String body) {
    final document = activeDocument;
    if (document == null || document.body == body) {
      return false;
    }
    _replace(document.copyWith(body: body));
    return true;
  }

  bool addActiveAttachment(String imagePath) {
    final document = activeDocument;
    final normalized = imagePath.trim();
    if (document == null ||
        normalized.isEmpty ||
        document.pendingImagePaths.contains(normalized)) {
      return false;
    }
    _replace(
      document.copyWith(
        pendingImagePaths: <String>[...document.pendingImagePaths, normalized],
      ),
    );
    return true;
  }

  bool removeActiveAttachment(String imagePath) {
    final document = activeDocument;
    if (document == null || !document.pendingImagePaths.contains(imagePath)) {
      return false;
    }
    _replace(
      document.copyWith(
        pendingImagePaths: document.pendingImagePaths
            .where((path) => path != imagePath)
            .toList(growable: false),
      ),
    );
    return true;
  }

  /// Applies the value returned by `ScrapController.saveDocument`.
  void markSaved(Scrap saved) {
    final document = activeDocument;
    if (document == null) {
      throw StateError('There is no active editor document to mark as saved.');
    }
    final existingId = document.scrap?.id;
    if (existingId != null && existingId != saved.id) {
      throw ArgumentError.value(
        saved.id,
        'saved',
        'The saved Scrap does not match the active document.',
      );
    }
    _replace(
      document.copyWith(
        scrap: saved,
        replaceScrap: true,
        body: saved.body,
        savedBody: saved.body,
        pendingImagePaths: const <String>[],
      ),
    );
  }

  /// Closes a clean tab. Dirty tabs return `false` so UI can ask what to do.
  bool closeDocument(String sessionId) {
    final document = _documentFor(sessionId);
    if (document == null || document.dirty) {
      return false;
    }
    _remove(sessionId);
    return true;
  }

  /// Implements the confirmed “Don't Save” action for a tab.
  bool discardDocument(String sessionId) {
    if (_documentFor(sessionId) == null) {
      return false;
    }
    _remove(sessionId);
    return true;
  }

  /// Replaces the current session with recoverable dirty documents.
  void restore(
    EditorRecoverySnapshot snapshot, {
    Iterable<Scrap> scraps = const <Scrap>[],
  }) {
    final scrapsById = <String, Scrap>{
      for (final scrap in scraps) scrap.id: scrap,
    };
    final restored = <EditorDocument>[];
    for (final recovery in snapshot.documents) {
      final scrap = recovery.scrapId == null
          ? null
          : scrapsById[recovery.scrapId];
      final document = EditorDocument(
        sessionId: recovery.sessionId,
        scrap: scrap,
        body: recovery.body,
        savedBody: scrap?.body ?? recovery.savedBody,
        pendingImagePaths: recovery.pendingImagePaths,
      );
      if (document.dirty) {
        restored.add(document);
      }
    }

    _documents = List<EditorDocument>.unmodifiable(restored);
    final requestedActive = snapshot.activeSessionId;
    _activeSessionId =
        requestedActive != null &&
            restored.any((document) => document.sessionId == requestedActive)
        ? requestedActive
        : restored.firstOrNull?.sessionId;
    notifyListeners();
  }

  /// Captures only dirty state; clean tabs do not need crash recovery.
  EditorRecoverySnapshot toSnapshot() {
    final dirtyDocuments = _documents
        .where((document) => document.dirty)
        .map(
          (document) => EditorRecoveryDocument(
            sessionId: document.sessionId,
            scrapId: document.scrap?.id,
            body: document.body,
            savedBody: document.savedBody,
            pendingImagePaths: document.pendingImagePaths,
          ),
        )
        .toList(growable: false);
    final currentActive = _activeSessionId;
    return EditorRecoverySnapshot(
      capturedAt: _now().toUtc(),
      activeSessionId:
          currentActive != null &&
              dirtyDocuments.any(
                (document) => document.sessionId == currentActive,
              )
          ? currentActive
          : dirtyDocuments.firstOrNull?.sessionId,
      documents: dirtyDocuments,
    );
  }

  String _newSessionId() {
    final id = _sessionIdGenerator().trim();
    if (id.isEmpty) {
      throw StateError('The editor session ID generator returned an empty ID.');
    }
    if (_documentFor(id) != null) {
      throw StateError('The editor session ID "$id" is already open.');
    }
    return id;
  }

  EditorDocument? _documentFor(String? sessionId) {
    if (sessionId == null) {
      return null;
    }
    for (final document in _documents) {
      if (document.sessionId == sessionId) {
        return document;
      }
    }
    return null;
  }

  void _replace(EditorDocument replacement) {
    _documents = <EditorDocument>[
      for (final document in _documents)
        if (document.sessionId == replacement.sessionId)
          replacement
        else
          document,
    ];
    notifyListeners();
  }

  void _remove(String sessionId) {
    final index = _documents.indexWhere(
      (document) => document.sessionId == sessionId,
    );
    final wasActive = _activeSessionId == sessionId;
    _documents = <EditorDocument>[
      for (final document in _documents)
        if (document.sessionId != sessionId) document,
    ];
    if (wasActive) {
      if (_documents.isEmpty) {
        _activeSessionId = null;
      } else {
        _activeSessionId =
            _documents[index.clamp(0, _documents.length - 1)].sessionId;
      }
    }
    notifyListeners();
  }
}
