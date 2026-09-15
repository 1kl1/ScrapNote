import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../domain/note.dart';
import '../editor/scrap_embed.dart';
import '../../infrastructure/vault/note_repository.dart';

class NoteEditorDocument {
  NoteEditorDocument({
    required this.sessionId,
    required this.note,
    required this.folder,
    required this.body,
    required this.savedBody,
    this.pendingImagePaths = const <String>[],
    this.preview = false,
    this.draftTitle = '',
    this.savedTitle = '',
  });

  final String draftTitle;
  final String savedTitle;
  final bool preview;
  final String sessionId;
  final Note? note;
  final String folder;
  final String body;
  final String savedBody;
  final List<String> pendingImagePaths;

  bool get dirty =>
      draftTitle != savedTitle ||
      body != savedBody ||
      pendingImagePaths.isNotEmpty;
  String get title {
    if (draftTitle.trim().isNotEmpty) return draftTitle.trim();
    if (note == null) return 'Untitled';
    final value = note!.copyWith(body: body).firstLineTitle;
    return value.isEmpty ? 'Untitled' : value;
  }

  NoteEditorDocument copyWith({
    Note? note,
    bool replaceNote = false,
    bool? preview,
    String? draftTitle,
    String? savedTitle,
    String? body,
    String? folder,
    String? savedBody,
    List<String>? pendingImagePaths,
  }) => NoteEditorDocument(
    sessionId: sessionId,
    draftTitle: draftTitle ?? this.draftTitle,
    savedTitle: savedTitle ?? this.savedTitle,
    preview: preview ?? this.preview,
    note: replaceNote ? note : (note ?? this.note),
    folder: folder ?? this.folder,
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
  Set<String> usedScrapIds({bool excludingActive = false}) {
    final openIds = _documents.map((d) => d.note?.id).toSet();
    return {
      for (final note in _notes)
        if (!openIds.contains(note.id)) ...ScrapEmbed.usedIds(note.body),
      for (final document in _documents)
        if (!excludingActive || document.sessionId != _activeSessionId)
          ...ScrapEmbed.usedIds(document.body),
    };
  }

  void updateTitle(String title) {
    final active = activeDocument;
    if (active == null || active.draftTitle == title) return;
    _replace(active.copyWith(draftTitle: title, preview: false));
  }

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

  List<Map<String, Object?>> recoveryDocuments() => [
    for (final document in _documents.where((d) => d.dirty))
      {
        'sessionId': document.sessionId,
        'noteId': document.note?.id,
        'folder': document.folder,
        'body': document.body,
        'savedBody': document.savedBody,
        'draftTitle': document.draftTitle,
        'savedTitle': document.savedTitle,
        'pendingImagePaths': document.pendingImagePaths,
      },
  ];

  void restoreRecovery(List<Map<String, dynamic>> rows) {
    if (_documents.isNotEmpty) return;
    _documents = [
      for (final row in rows)
        NoteEditorDocument(
          sessionId: row['sessionId'] as String,
          note: _notes.where((n) => n.id == row['noteId']).firstOrNull,
          folder: row['folder'] as String,
          body: row['body'] as String,
          savedBody: row['savedBody'] as String,
          draftTitle: row['draftTitle'] as String,
          savedTitle: row['savedTitle'] as String,
          pendingImagePaths: List<String>.from(
            row['pendingImagePaths'] as List,
          ),
        ),
    ];
    _activeSessionId = _documents.lastOrNull?.sessionId;
    notifyListeners();
  }

  Future<void> reloadAfterSync() async {
    final repository = _repository;
    if (repository == null) return;
    final notes = await repository.listNotes();
    final folders = await repository.listFolders();
    final byId = {for (final note in notes) note.id: note};
    _notes = notes;
    _folders = folders;
    _documents = [
      for (final document in _documents)
        if (document.dirty || document.note == null)
          document
        else if (byId[document.note!.id] case final saved?)
          document.copyWith(
            note: saved,
            folder: saved.folder,
            body: saved.body,
            savedBody: saved.body,
            draftTitle: saved.title,
            savedTitle: saved.title,
          ),
    ];
    if (activeDocument == null) {
      _activeSessionId = _documents.lastOrNull?.sessionId;
    }
    if (!_folders.any((f) => f.id == _selectedFolder)) _selectedFolder = '';
    notifyListeners();
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

  Future<bool> moveNote(String id, String folder) => _changeTree(
    () => _repository!.moveNote(id, folder),
    movedNote: id,
    destination: folder,
  );
  Future<bool> moveFolder(String folder, String parent) => _changeTree(
    () => _repository!.moveFolder(folder, parent),
    movedFolder: folder,
    destination: path.join(parent, path.basename(folder)),
  );
  Future<bool> deleteNote(String id) =>
      _changeTree(() => _repository!.deleteNote(id), deletedNote: id);
  Future<bool> deleteFolder(String folder) => _changeTree(
    () => _repository!.deleteFolder(folder),
    deletedFolder: folder,
  );

  bool _inside(String folder, String parent) =>
      folder == parent || path.isWithin(parent, folder);

  Future<bool> _changeTree(
    Future<void> Function() operation, {
    String? movedNote,
    String? movedFolder,
    String? destination,
    String? deletedNote,
    String? deletedFolder,
  }) async {
    if (_repository == null || _saving) return false;
    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation();
      _notes = await _repository!.listNotes();
      _folders = await _repository!.listFolders();
      final byId = {for (final note in _notes) note.id: note};
      final documents = <NoteEditorDocument>[];
      for (final document in _documents) {
        if ((deletedNote != null && document.note?.id == deletedNote) ||
            (deletedFolder != null &&
                _inside(document.folder, deletedFolder))) {
          continue;
        }
        var folder = document.folder;
        if (movedNote != null && document.note?.id == movedNote) {
          folder = destination!;
        }
        if (movedFolder != null && _inside(folder, movedFolder)) {
          final suffix = path.relative(folder, from: movedFolder);
          folder = suffix == '.'
              ? destination!
              : path.join(destination!, suffix);
        }
        final from = path.join(vaultPath!, 'notes', document.folder);
        final to = path.join(vaultPath!, 'notes', folder);
        documents.add(
          document.copyWith(
            folder: folder,
            note: byId[document.note?.id],
            body: NoteRepository.rebaseBody(document.body, from, to),
            savedBody: NoteRepository.rebaseBody(document.savedBody, from, to),
          ),
        );
      }
      _documents = documents;
      if (!_documents.any((d) => d.sessionId == _activeSessionId)) {
        _activeSessionId = _documents.firstOrNull?.sessionId;
      }
      if (movedFolder != null && _inside(_selectedFolder, movedFolder)) {
        final suffix = path.relative(_selectedFolder, from: movedFolder);
        _selectedFolder = suffix == '.'
            ? destination!
            : path.join(destination!, suffix);
      }
      if (deletedFolder != null && _inside(_selectedFolder, deletedFolder)) {
        _selectedFolder = '';
      }
      return true;
    } on FileSystemException catch (error) {
      _errorMessage = '파일 작업을 완료하지 못했습니다. ${error.message}';
      return false;
    } on FormatException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
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
      draftTitle: note.title,
      savedTitle: note.title,
      preview: true,
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

  void editActive() {
    final active = activeDocument;
    if (active != null) _replace(active.copyWith(preview: false));
  }

  void updateBody(String body) {
    final active = activeDocument;
    if (active == null || active.body == body) return;
    _replace(active.copyWith(body: body, preview: false));
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
    if (active.draftTitle.trim().isEmpty &&
        active.body.trim().isEmpty &&
        active.pendingImagePaths.isEmpty) {
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
              title: active.draftTitle,
              attachmentPaths: active.pendingImagePaths,
            )
          : await repository.updateNote(
              active.note!,
              active.body,
              title: active.draftTitle,
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
          draftTitle: saved.title,
          savedTitle: saved.title,
          preview: true,
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
