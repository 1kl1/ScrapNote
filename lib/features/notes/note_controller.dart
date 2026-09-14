import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../domain/note.dart';
import '../../infrastructure/vault/note_repository.dart';

class NoteEditorDocument {
  NoteEditorDocument({
    required this.sessionId,
    required this.note,
    required this.folder,
    required this.body,
    required this.savedBody,
    this.pendingImagePaths = const <String>[],
  });

  final String sessionId;
  final Note? note;
  final String folder;
  final String body;
  final String savedBody;
  final List<String> pendingImagePaths;

  bool get dirty => body != savedBody || pendingImagePaths.isNotEmpty;
  String get title {
    if (note == null) return 'Untitled';
    final value = note!.copyWith(body: body).firstLineTitle;
    return value.isEmpty ? 'Untitled' : value;
  }

  NoteEditorDocument copyWith({
    Note? note,
    bool replaceNote = false,
    String? body,
    String? savedBody,
    List<String>? pendingImagePaths,
  }) => NoteEditorDocument(
    sessionId: sessionId,
    note: replaceNote ? note : (note ?? this.note),
    folder: folder,
    body: body ?? this.body,
    savedBody: savedBody ?? this.savedBody,
    pendingImagePaths: pendingImagePaths ?? this.pendingImagePaths,
  );
}

class NoteController extends ChangeNotifier {
  NoteController({NoteRepository Function(Directory)? repositoryFactory})
    : _repositoryFactory = repositoryFactory ?? NoteRepository.new;

  final NoteRepository Function(Directory) _repositoryFactory;
  NoteRepository? _repository;
  List<NoteFolder> _folders = const <NoteFolder>[];
  List<Note> _notes = const <Note>[];
  List<NoteEditorDocument> _documents = const <NoteEditorDocument>[];
  String? _activeSessionId;
  String _selectedFolder = '';
  bool _loading = false;
  bool _saving = false;
  String? _errorMessage;

  List<NoteFolder> get folders => List.unmodifiable(_folders);
  List<Note> get notes => List.unmodifiable(_notes);
  List<NoteEditorDocument> get documents => List.unmodifiable(_documents);
  NoteEditorDocument? get activeDocument =>
      _documents.where((doc) => doc.sessionId == _activeSessionId).firstOrNull;
  String? get activeSessionId => _activeSessionId;
  String get selectedFolder => _selectedFolder;
  bool get loading => _loading;
  bool get saving => _saving;
  bool get hasDirtyDocuments => _documents.any((document) => document.dirty);
  String? get errorMessage => _errorMessage;
  String? get vaultPath => _repository?.root.path;

  Future<void> connect(String vaultPath) async {
    if (_repository?.root.path == vaultPath) return;
    _loading = true;
    notifyListeners();
    try {
      final repository = _repositoryFactory(Directory(vaultPath));
      await repository.initialize();
      _folders = await repository.listFolders();
      _notes = await repository.listNotes();
      _repository = repository;
      _documents = const <NoteEditorDocument>[];
      _activeSessionId = null;
      _selectedFolder = '';
      _errorMessage = null;
    } on FileSystemException catch (error) {
      _errorMessage = 'Note 폴더를 읽지 못했습니다. ${error.message}';
    } on FormatException catch (error) {
      _errorMessage = error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void selectFolder(String folder) {
    if (_selectedFolder == folder) return;
    _selectedFolder = folder;
    notifyListeners();
  }

  Future<bool> createFolder(String name) async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      final folder = await repository.createFolder(
        name,
        parent: _selectedFolder,
      );
      _folders = await repository.listFolders();
      _selectedFolder = folder.id;
      _errorMessage = null;
      notifyListeners();
      return true;
    } on FileSystemException catch (error) {
      _errorMessage = '폴더를 만들지 못했습니다. ${error.message}';
    } on FormatException catch (error) {
      _errorMessage = error.message;
    }
    notifyListeners();
    return false;
  }

  NoteEditorDocument newDocument() {
    final document = NoteEditorDocument(
      sessionId: const Uuid().v4(),
      note: null,
      folder: _selectedFolder,
      body: '',
      savedBody: '',
    );
    _documents = <NoteEditorDocument>[..._documents, document];
    _activeSessionId = document.sessionId;
    notifyListeners();
    return document;
  }

  void openNote(String noteId) {
    final open = _documents.where((doc) => doc.note?.id == noteId).firstOrNull;
    if (open != null) {
      _activeSessionId = open.sessionId;
      notifyListeners();
      return;
    }
    final note = _notes.where((item) => item.id == noteId).firstOrNull;
    if (note == null) return;
    final document = NoteEditorDocument(
      sessionId: const Uuid().v4(),
      note: note,
      folder: note.folder,
      body: note.body,
      savedBody: note.body,
    );
    _documents = <NoteEditorDocument>[..._documents, document];
    _activeSessionId = document.sessionId;
    notifyListeners();
  }

  void activate(String sessionId) {
    if (_documents.any((doc) => doc.sessionId == sessionId)) {
      _activeSessionId = sessionId;
      notifyListeners();
    }
  }

  void updateBody(String body) {
    final active = activeDocument;
    if (active == null || active.body == body) return;
    _replace(active.copyWith(body: body));
  }

  void addAttachment(String imagePath) {
    final active = activeDocument ?? newDocument();
    if (active.pendingImagePaths.contains(imagePath)) return;
    _replace(
      active.copyWith(
        pendingImagePaths: <String>[...active.pendingImagePaths, imagePath],
      ),
    );
  }

  void removeAttachment(String imagePath) {
    final active = activeDocument;
    if (active == null) return;
    _replace(
      active.copyWith(
        pendingImagePaths: active.pendingImagePaths
            .where((item) => item != imagePath)
            .toList(),
      ),
    );
  }

  Future<bool> saveActive() async {
    if (_saving) return false;
    final repository = _repository;
    final active = activeDocument;
    if (repository == null || active == null) return false;
    if (active.body.trim().isEmpty && active.pendingImagePaths.isEmpty) {
      _errorMessage = '빈 Note는 저장하지 않았습니다.';
      notifyListeners();
      return false;
    }
    _saving = true;
    notifyListeners();
    try {
      final saved = active.note == null
          ? await repository.createNote(
              active.body,
              folder: active.folder,
              attachmentPaths: active.pendingImagePaths,
            )
          : await repository.updateNote(
              active.note!,
              active.body,
              attachmentPaths: active.pendingImagePaths,
            );
      _notes = <Note>[saved, ..._notes.where((note) => note.id != saved.id)]
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      _replace(
        active.copyWith(
          note: saved,
          replaceNote: true,
          body: saved.body,
          savedBody: saved.body,
          pendingImagePaths: const <String>[],
        ),
      );
      _errorMessage = null;
      return true;
    } on FileSystemException catch (error) {
      _errorMessage = 'Note를 저장하지 못했습니다. ${error.message}';
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  bool close(String sessionId) {
    final document = _documents
        .where((doc) => doc.sessionId == sessionId)
        .firstOrNull;
    if (document == null || document.dirty) return false;
    _remove(sessionId);
    return true;
  }

  bool discard(String sessionId) {
    if (!_documents.any((doc) => doc.sessionId == sessionId)) return false;
    _remove(sessionId);
    return true;
  }

  List<String> activeImagePaths() {
    final active = activeDocument;
    if (active == null) return const <String>[];
    final persisted = active.note == null
        ? const <String>[]
        : active.note!.assets
              .map(
                (asset) => path.normalize(
                  path.join(
                    path.dirname(active.note!.filePath),
                    asset.relativePath,
                  ),
                ),
              )
              .toList(growable: false);
    return <String>[...persisted, ...active.pendingImagePaths];
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _replace(NoteEditorDocument replacement) {
    _documents = <NoteEditorDocument>[
      for (final document in _documents)
        if (document.sessionId == replacement.sessionId)
          replacement
        else
          document,
    ];
    notifyListeners();
  }

  void _remove(String sessionId) {
    final index = _documents.indexWhere((doc) => doc.sessionId == sessionId);
    final wasActive = _activeSessionId == sessionId;
    _documents = _documents.where((doc) => doc.sessionId != sessionId).toList();
    if (wasActive) {
      _activeSessionId = _documents.isEmpty
          ? null
          : _documents[index.clamp(0, _documents.length - 1)].sessionId;
    }
    notifyListeners();
  }
}
