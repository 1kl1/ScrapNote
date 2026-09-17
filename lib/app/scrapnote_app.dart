// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/sync/sync_account_page.dart';
import '../infrastructure/sync/sync_manifest.dart';
import '../infrastructure/sync/vault_synchronizer.dart';
import '../infrastructure/sync/sync_vault_summary.dart';
import '../features/expenses/expense_controller.dart';
import '../features/expenses/expenses_view.dart';

import 'package:file_selector/file_selector.dart';
import '../domain/scrap.dart';
import '../features/editor/inline_image.dart';
import '../features/editor/scrap_embed.dart';
import '../features/notes/folder_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as path;
import 'package:scrapnote/app/scrapnote_shell.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/app/vault_onboarding.dart';
import 'package:scrapnote/core/design/scrapnote_tokens.dart';
import 'package:scrapnote/features/editor/editor_document.dart';
import 'package:scrapnote/features/editor/editor_session_controller.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/features/notes/notes_workspace.dart';
import 'package:scrapnote/features/scraps/scrap_controller.dart';
import 'package:scrapnote/features/scraps/scraps_view.dart';
import 'package:scrapnote/features/timeline/timeline_view.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_store.dart';
import 'package:scrapnote/infrastructure/platform/editor_commands.dart';
import 'package:scrapnote/infrastructure/platform/image_clipboard.dart';
import 'package:scrapnote/infrastructure/platform/window_close_guard.dart';

typedef ImagePathPicker = Future<List<String>> Function();
typedef ClipboardImageReader = Future<String?> Function();

class ScrapnoteApp extends StatelessWidget {
  const ScrapnoteApp({
    super.key,
    this.controller,
    this.syncClient,
    this.editorSessionController,
    this.noteController,
    this.expenseController,
    this.recoveryStore,
    this.windowCloseGuard,
    this.imagePathPicker,
    this.clipboardImageReader,
    this.syncSummaryLoader = loadSyncVaultSummary,
    this.vaultSynchronizer = synchronizeVault,
    this.initializeController = true,
    this.installWindowCloseGuard = true,
  });

  final ScrapController? controller;
  final SupabaseClient? syncClient;
  final EditorSessionController? editorSessionController;
  final NoteController? noteController;
  final ExpenseController? expenseController;
  final EditorRecoveryStore? recoveryStore;
  final WindowCloseGuard? windowCloseGuard;
  final ImagePathPicker? imagePathPicker;
  final ClipboardImageReader? clipboardImageReader;
  final SyncVaultSummaryLoader syncSummaryLoader;
  final VaultSynchronizer vaultSynchronizer;
  final bool initializeController;
  final bool installWindowCloseGuard;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scrapnote',
      debugShowCheckedModeBanner: false,
      theme: ScrapnoteTheme.materialTheme,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      home: ScrapnoteWorkspace(
        controller: controller,
        syncClient: syncClient,
        editorSessionController: editorSessionController,
        noteController: noteController,
        expenseController: expenseController,
        recoveryStore: recoveryStore,
        windowCloseGuard: windowCloseGuard,
        imagePathPicker: imagePathPicker,
        clipboardImageReader: clipboardImageReader,
        syncSummaryLoader: syncSummaryLoader,
        vaultSynchronizer: vaultSynchronizer,
        initializeController: initializeController,
        installWindowCloseGuard: installWindowCloseGuard,
      ),
    );
  }
}

class ScrapnoteWorkspace extends StatefulWidget {
  const ScrapnoteWorkspace({
    super.key,
    this.controller,
    this.syncClient,
    this.editorSessionController,
    this.noteController,
    this.expenseController,
    this.recoveryStore,
    this.windowCloseGuard,
    this.imagePathPicker,
    this.clipboardImageReader,
    this.syncSummaryLoader = loadSyncVaultSummary,
    this.vaultSynchronizer = synchronizeVault,
    this.initializeController = true,
    this.installWindowCloseGuard = true,
  });

  final ScrapController? controller;
  final SupabaseClient? syncClient;
  final EditorSessionController? editorSessionController;
  final NoteController? noteController;
  final ExpenseController? expenseController;
  final EditorRecoveryStore? recoveryStore;
  final WindowCloseGuard? windowCloseGuard;
  final ImagePathPicker? imagePathPicker;
  final ClipboardImageReader? clipboardImageReader;
  final SyncVaultSummaryLoader syncSummaryLoader;
  final VaultSynchronizer vaultSynchronizer;
  final bool initializeController;
  final bool installWindowCloseGuard;

  @override
  State<ScrapnoteWorkspace> createState() => _ScrapnoteWorkspaceState();
}

class _ScrapnoteWorkspaceState extends State<ScrapnoteWorkspace>
    with WidgetsBindingObserver {
  static const _imageExtensions = <String>{
    '.bmp',
    '.gif',
    '.heic',
    '.heif',
    '.jpeg',
    '.jpg',
    '.png',
    '.tif',
    '.tiff',
    '.webp',
  };

  late final ScrapController _controller;
  late final EditorSessionController _editorSession;
  late final NoteController _noteController;
  late final ExpenseController _expenseController;
  late final EditorRecoveryStore _recoveryStore;
  late final WindowCloseGuard _windowCloseGuard;
  late final EditorCommands _editorCommands;
  late final Listenable _workspaceListenable;
  late final bool _ownsController;
  late final bool _ownsEditorSession;
  late final bool _ownsNoteController;
  late final ImagePathPicker _imagePathPicker;
  late final ClipboardImageReader _clipboardImageReader;
  final TextEditingController _editorController = TextEditingController();
  final TextEditingController _noteTextController = TextEditingController();
  final Set<String> _temporaryImagePaths = <String>{};

  ScrapnoteSection _section = ScrapnoteSection.scraps;
  late DateTime _selectedDate;
  Timer? _recoveryTimer;
  bool _syncInFlight = false;
  String _syncStatus = '아직 동기화하지 않았습니다.';
  String? _boundSessionId;
  String? _boundNoteSessionId;
  String? _preparedVaultPath;
  String? _notesRecoveryVault;
  Future<void> _recoveryWrite = Future.value();
  String? _localError;
  bool _syncingEditor = false;
  bool _syncingNoteEditor = false;
  bool _saveInFlight = false;
  bool _readingClipboard = false;
  bool _choosingImages = false;
  bool _recoveryLoaded = false;
  bool _preparingEditorSession = false;
  bool _windowGuardStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ?? ScrapController();
    _editorSession =
        widget.editorSessionController ?? EditorSessionController();
    _noteController = widget.noteController ?? NoteController();
    _expenseController = widget.expenseController ?? ExpenseController();
    _recoveryStore = widget.recoveryStore ?? EditorRecoveryStore();
    _windowCloseGuard = widget.windowCloseGuard ?? WindowCloseGuard();
    _editorCommands = EditorCommands();
    _workspaceListenable = Listenable.merge(<Listenable>[
      _controller,
      _editorSession,
      _noteController,
    ]);
    _ownsController = widget.controller == null;
    _ownsEditorSession = widget.editorSessionController == null;
    _ownsNoteController = widget.noteController == null;
    _imagePathPicker = widget.imagePathPicker ?? _pickImageFiles;
    _clipboardImageReader =
        widget.clipboardImageReader ?? ImageClipboard.readImagePath;
    _editorController.addListener(_handleEditorTextChanged);
    _noteTextController.addListener(_handleNoteTextChanged);
    _editorSession.addListener(_handleEditorSessionChanged);
    _noteController.addListener(_handleNoteControllerChanged);
    FocusManager.instance.addEarlyKeyEventHandler(_handleGlobalKeyEvent);

    final today = DateTime.now();
    _selectedDate = DateTime(today.year, today.month, today.day);
    if (widget.initializeController) {
      unawaited(_initialize());
    } else if (_controller.hasVault) {
      unawaited(_prepareEditorSession());
      unawaited(_noteController.connect(_controller.vaultPath!));
      unawaited(_expenseController.connect(_controller.vaultPath!));
      unawaited(_restoreSyncStatus());
    }
    if (widget.installWindowCloseGuard) {
      unawaited(_startWindowCloseGuard());
      unawaited(
        _editorCommands.start(
          onSaveRequested: _handleNativeSaveRequested,
          onNewDocumentRequested: _handleNativeNewDocumentRequested,
          onCloseDocumentRequested: _handleNativeCloseDocumentRequested,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.expenseController == null) _expenseController.dispose();
    _recoveryTimer?.cancel();
    unawaited(_persistRecovery());
    if (_windowGuardStarted) {
      unawaited(_windowCloseGuard.stop());
    }
    unawaited(_editorCommands.stop());
    _editorController
      ..removeListener(_handleEditorTextChanged)
      ..dispose();
    _noteTextController
      ..removeListener(_handleNoteTextChanged)
      ..dispose();
    _editorSession.removeListener(_handleEditorSessionChanged);
    _noteController.removeListener(_handleNoteControllerChanged);
    FocusManager.instance.removeEarlyKeyEventHandler(_handleGlobalKeyEvent);
    final pending = {
      for (final document in _editorSession.documents)
        ...document.pendingImagePaths,
      for (final document in _noteController.documents)
        ...document.pendingImagePaths,
    };
    for (final imagePath in _temporaryImagePaths.difference(pending)) {
      unawaited(_deleteTemporaryImage(imagePath));
    }
    if (_ownsEditorSession) {
      _editorSession.dispose();
    }
    if (_ownsNoteController) {
      _noteController.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _workspaceListenable,
      builder: (context, _) {
        if (_controller.hasVault &&
            _editorSession.documents.isEmpty &&
            _preparedVaultPath != _controller.vaultPath &&
            !_preparingEditorSession) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(_prepareEditorSession());
            }
          });
        }
        final error =
            _localError ??
            _controller.errorMessage ??
            _noteController.errorMessage;
        return ScrapnoteShell(
          section: _section,
          onSectionChanged: (section) => setState(() => _section = section),
          vaultPath: _controller.vaultPath,
          onSync: () => unawaited(_openSync()),
          onChooseVault: _syncInFlight ? null : () => unawaited(_chooseVault()),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_controller.loading)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: ScrapnoteTokens.signalOrange,
                  backgroundColor: ScrapnoteTokens.paperSunken,
                ),
              if (error != null)
                _ErrorStrip(message: error, onDismiss: _dismissError),
              Expanded(
                child: AbsorbPointer(
                  absorbing: _syncInFlight,
                  child: _controller.hasVault
                      ? _buildSection()
                      : VaultOnboarding(
                          loading: _controller.loading,
                          onChooseVault: () => unawaited(_chooseVault()),
                        ),
                ),
              ),
              if (widget.syncClient != null)
                _SyncStatusLine(
                  status: _syncInFlight ? '동기화 중…' : _syncStatus,
                  syncing: _syncInFlight,
                  onSync: !_controller.hasVault || _controller.loading
                      ? null
                      : () => unawaited(_requestSync()),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_persistRecovery());
    }
  }

  Future<void> _requestSync() async {
    if (_syncInFlight) return;
    if (widget.syncClient?.auth.currentUser == null) {
      await _openSync();
      return;
    }
    try {
      final status = await _performSync();
      if (mounted) setState(() => _syncStatus = status);
    } on SyncConflicts {
      if (mounted) await _openSync();
    }
  }

  Future<void> _openSync() async {
    if (_syncInFlight) return;
    final client = widget.syncClient;
    final vaultPath = _controller.vaultPath;
    if (client == null) {
      setState(
        () => _localError =
            '계정 연결을 시작하지 못했습니다. 앱을 다시 열어 주세요. 로컬 편집은 계속 사용할 수 있습니다.',
      );
      return;
    }
    if (vaultPath == null) {
      setState(() => _localError = '동기화할 로컬 Vault 폴더를 먼저 선택해 주세요.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SyncAccountPage(
          client: client,
          status: _syncStatus,
          vaultPath: vaultPath,
          summaryLoader: widget.syncSummaryLoader,
          onSync: (resolutions) => _performSync(resolutions: resolutions),
        ),
      ),
    );
    if (mounted && client.auth.currentUser == null) {
      setState(() => _syncStatus = '기기에 저장됨 · 로그인하면 다른 기기와 연결할 수 있습니다.');
    }
  }

  Future<void> _restoreSyncStatus() async {
    final vaultPath = _controller.vaultPath;
    if (widget.syncClient == null || vaultPath == null) return;
    try {
      final summary = await widget.syncSummaryLoader(vaultPath);
      if (!mounted) return;
      final signedIn = widget.syncClient!.auth.currentUser != null;
      setState(() {
        _syncStatus = !signedIn
            ? '기기에 저장됨 · 로그인하면 다른 기기와 연결할 수 있습니다.'
            : summary.lastSyncedAt == null
            ? '로그인됨 · 아직 이 Vault를 동기화하지 않았습니다.'
            : '마지막 동기화 · ${_formatSyncTime(summary.lastSyncedAt!.toLocal())}';
      });
    } on FileSystemException {
      // The account page will surface detailed Vault read errors if opened.
    }
  }

  Future<String> _performSync({
    Map<String, SyncResolution> resolutions = const {},
  }) async {
    final client = widget.syncClient;
    final vaultPath = _controller.vaultPath;
    if (_syncInFlight ||
        client?.auth.currentUser == null ||
        vaultPath == null ||
        _controller.loading ||
        _controller.saving ||
        _saveInFlight ||
        _readingClipboard ||
        _choosingImages ||
        _noteController.saving ||
        _noteController.loading ||
        _expenseController.saving ||
        _expenseController.loading) {
      return '저장소와 로그인 상태를 확인한 뒤 다시 시도해 주세요.';
    }
    if (!mounted || _syncInFlight) return _syncStatus;
    setState(() {
      _syncInFlight = true;
      _syncStatus = '동기화 중…';
    });
    try {
      if (!await _saveAllDirtyDocuments()) {
        return _syncStatus = '저장하지 못한 문서가 있습니다. 내용을 확인한 뒤 다시 시도해 주세요.';
      }
      await widget.vaultSynchronizer(vaultPath, client!, resolutions);
      if (!mounted) return _syncStatus;
      await _controller.reload();
      _editorSession.refreshSavedDocuments(_controller.scraps);
      await _noteController.reloadAfterSync();
      await _expenseController.reloadAfterSync();
      _syncStatus = '동기화 완료 · ${_formatSyncTime(DateTime.now())}';
      return _syncStatus;
    } on SyncConflicts {
      _syncStatus = '동기화 충돌 · 계정 및 동기화에서 사용할 내용을 선택해 주세요.';
      rethrow;
    } on FormatException catch (error) {
      _syncStatus = error.message;
      return _syncStatus;
    } on Exception {
      _syncStatus = '동기화하지 못했습니다 · 기기에는 저장됨. 연결 후 동기화 버튼을 다시 눌러 주세요.';
      return _syncStatus;
    } finally {
      if (mounted) setState(() => _syncInFlight = false);
    }
  }

  Widget _buildSection() {
    final active = _editorSession.activeDocument;
    return switch (_section) {
      ScrapnoteSection.scraps => ScrapsView(
        scraps: _controller.scraps
            .where(
              (scrap) => !_noteController.usedScrapIds().contains(scrap.id),
            )
            .toList(),
        imageDirectory: path.join(_controller.vaultPath!, 'scraps'),
        onDeleteScrap: (id) => unawaited(_deleteScrap(id)),
        tabs: <ScrapEditorTabData>[
          for (final document in _editorSession.documents)
            ScrapEditorTabData(
              id: document.sessionId,
              title: document.displayName,
              dirty: document.dirty,
            ),
        ],
        activeTabId: _editorSession.activeSessionId,
        activeScrapId: active?.scrap?.id,
        activeScrap: active?.scrap,
        controller: _editorController,
        saving: _controller.saving || _saveInFlight,
        pendingImagePaths: active?.pendingImagePaths ?? const <String>[],
        savedImagePaths: _scrapImagePaths(active),
        onNewDocument: _newDocument,
        onScrapSelected: _openScrap,
        onTabSelected: _activateDocument,
        onTabClosed: (sessionId) => unawaited(_requestCloseTab(sessionId)),
        onCloseActive: () => unawaited(_closeActiveDocument()),
        onSave: () => unawaited(_saveActiveDocument()),
        onChooseImages: () => unawaited(_chooseImages()),
        onImagesDropped: _addImagePaths,
        onPasteImage: _pasteImage,
        onRemoveImage: _removeImage,
        onRetryLocation: active?.scrap == null
            ? null
            : () => unawaited(_retryActiveScrapLocation()),
        onSetManualLocation: active?.scrap == null
            ? null
            : (location) => unawaited(_setActiveScrapLocation(location)),
        onOpenLocationSettings: active?.scrap == null
            ? null
            : () => unawaited(_controller.openLocationPermissionSettings()),
      ),
      ScrapnoteSection.notes => NotesWorkspace(
        scraps: _controller.scraps
            .where(
              (scrap) => !_noteController
                  .usedScrapIds(excludingActive: true)
                  .contains(scrap.id),
            )
            .toList(),
        onInsertScrap: _insertScrap,
        onEmbeddedImageAdded: (imagePath) {
          _temporaryImagePaths.add(imagePath);
          _noteController.addAttachment(imagePath);
        },
        noteController: _noteController,
        textController: _noteTextController,
        onCreateFolder: () => unawaited(_createNoteFolder()),
        onCreateNote: _noteController.newDocument,
        onSave: () => unawaited(_saveActiveNote()),
        onCloseTab: (sessionId) => unawaited(_requestCloseNoteTab(sessionId)),
        onChooseImages: () => unawaited(_chooseImages()),
        onPasteImage: _pasteImage,
        onImagesDropped: _addImagePaths,
        onRemoveImage: _removeImage,
      ),
      ScrapnoteSection.expenses => ExpensesView(controller: _expenseController),
      ScrapnoteSection.timeline => TimelineView(
        scraps: _controller.scraps,
        selectedDate: _selectedDate,
        vaultPath: _controller.vaultPath!,
        onDateChanged: (date) => setState(() => _selectedDate = date),
      ),
    };
  }

  Future<void> _initialize() async {
    await _controller.initialize();
    if (!mounted || !_controller.hasVault) {
      return;
    }
    await _prepareEditorSession();
    await _noteController.connect(_controller.vaultPath!);
    await _expenseController.connect(_controller.vaultPath!);
    await _restoreNotesRecovery();
    await _restoreSyncStatus();
  }

  Future<void> _prepareEditorSession() async {
    if (_preparingEditorSession) {
      return;
    }
    _preparingEditorSession = true;
    try {
      if (!_recoveryLoaded && _editorSession.documents.isEmpty) {
        try {
          final snapshot = await _recoveryStore.load();
          if (snapshot != null) {
            _editorSession.restore(snapshot, scraps: _controller.scraps);
          }
        } on Exception catch (error) {
          if (mounted) {
            setState(() {
              _localError = '복구 초안을 읽지 못했습니다. $error';
            });
          }
        }
        _recoveryLoaded = true;
      }
      if (_editorSession.documents.isEmpty) {
        _editorSession.newDocument();
      } else {
        _syncEditorController();
      }
    } finally {
      _preparedVaultPath = _controller.vaultPath;
      _preparingEditorSession = false;
    }
  }

  Future<void> _startWindowCloseGuard() async {
    try {
      await _windowCloseGuard.start(_handleWindowCloseRequest);
      _windowGuardStarted = true;
    } on MissingPluginException {
      // Other platforms currently rely on their native lifecycle behavior.
    } on PlatformException {
      // Editing must remain available if a desktop runner lacks the channel.
    }
  }

  Future<void> _handleNativeSaveRequested() async {
    if (_syncInFlight) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!mounted || !_controller.hasVault) return;
    if (_section == ScrapnoteSection.scraps) {
      await _saveActiveDocument();
    } else if (_section == ScrapnoteSection.notes) {
      await _saveActiveNote();
    }
  }

  Future<void> _handleNativeNewDocumentRequested() async {
    if (_syncInFlight) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!mounted || !_controller.hasVault) return;
    if (_section == ScrapnoteSection.scraps) {
      _newDocument();
    } else if (_section == ScrapnoteSection.notes) {
      _noteController.newDocument();
    }
  }

  Future<void> _handleNativeCloseDocumentRequested() async {
    if (_syncInFlight) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    await _closeActiveDocument();
  }

  void _handleEditorTextChanged() {
    if (_syncingEditor) {
      return;
    }
    _editorSession.updateActiveBody(_editorController.text);
  }

  void _handleNoteTextChanged() {
    if (!_syncingNoteEditor) {
      _noteController.updateBody(_noteTextController.text);
    }
  }

  KeyEventResult _handleGlobalKeyEvent(KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent == false ||
        event is! KeyDownEvent ||
        (!HardwareKeyboard.instance.isMetaPressed &&
            !HardwareKeyboard.instance.isControlPressed) ||
        (!_controller.hasVault || _syncInFlight)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      if (_section == ScrapnoteSection.notes) {
        unawaited(_saveActiveNote());
        return KeyEventResult.handled;
      }
      if (_section == ScrapnoteSection.scraps) {
        unawaited(_saveActiveDocument());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      if (_section == ScrapnoteSection.notes) {
        _noteController.newDocument();
      } else if (_section == ScrapnoteSection.scraps) {
        _newDocument();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      if (_section == ScrapnoteSection.scraps ||
          _section == ScrapnoteSection.notes) {
        unawaited(_closeActiveDocument());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  void _handleEditorSessionChanged() {
    _syncEditorController();
    _scheduleRecovery();
  }

  void _handleNoteControllerChanged() {
    _scheduleRecovery();
    final active = _noteController.activeDocument;
    if (active == null) {
      _boundNoteSessionId = null;
      if (_noteTextController.text.isNotEmpty) {
        _setNoteText('');
      }
      return;
    }
    if (_boundNoteSessionId != active.sessionId ||
        _noteTextController.text != active.body) {
      _boundNoteSessionId = active.sessionId;
      _setNoteText(active.body);
    }
  }

  void _setNoteText(String value) {
    _syncingNoteEditor = true;
    _noteTextController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncingNoteEditor = false;
  }

  void _syncEditorController() {
    final active = _editorSession.activeDocument;
    if (active == null) {
      _boundSessionId = null;
      if (_editorController.text.isNotEmpty) {
        _setEditorText('');
      }
      return;
    }

    if (_boundSessionId != active.sessionId ||
        _editorController.text != active.body) {
      _boundSessionId = active.sessionId;
      _setEditorText(active.body);
    }
  }

  void _setEditorText(String value) {
    _syncingEditor = true;
    _editorController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncingEditor = false;
  }

  void _scheduleRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_persistRecovery()),
    );
  }

  Future<void> _restoreNotesRecovery() async {
    final vault = _noteController.vaultPath;
    if (vault == null || _notesRecoveryVault == vault) return;
    try {
      final rows = await _recoveryStore.loadNotes(vault);
      if (mounted) _noteController.restoreRecovery(rows);
      _notesRecoveryVault = vault;
    } on Exception {
      if (mounted) {
        setState(() => _localError = '노트 복구 파일을 읽지 못했습니다. 원본 복구 파일은 유지됩니다.');
      }
    }
  }

  Future<void> _persistRecovery() {
    final snapshot = _editorSession.toSnapshot();
    final vault = _noteController.vaultPath;
    final notes = _noteController.recoveryDocuments();
    final saveNotes = vault != null && vault == _notesRecoveryVault;
    return _recoveryWrite = _recoveryWrite.then((_) async {
      try {
        await _recoveryStore.save(snapshot);
        if (saveNotes) await _recoveryStore.saveNotes(vault, notes);
      } on Exception catch (error) {
        if (mounted) setState(() => _localError = '복구 초안을 저장하지 못했습니다. $error');
      }
    });
  }

  void _newDocument() {
    if (_saveInFlight) {
      return;
    }
    _editorSession.newDocument();
  }

  void _openScrap(String scrapId) {
    if (_saveInFlight) {
      return;
    }
    final scrap = _controller.scraps
        .where((candidate) => candidate.id == scrapId)
        .firstOrNull;
    if (scrap != null) {
      _editorSession.openScrap(scrap);
    }
  }

  Future<void> _deleteScrap(String id) async {
    if (_saveInFlight) return;
    if (await _controller.deleteScrap(id)) {
      for (final document
          in _editorSession.documents
              .where((d) => d.scrap?.id == id)
              .toList()) {
        await _discardDocument(document);
      }
      await _persistRecovery();
    }
  }

  void _insertScrap(Scrap scrap) {
    if (_noteController.saving ||
        _noteController
            .usedScrapIds(excludingActive: true)
            .contains(scrap.id)) {
      return;
    }
    if (_noteController.activeDocument == null) _noteController.newDocument();
    final note = _noteController.activeDocument!;
    final sourceDirectory = path.join(_controller.vaultPath!, 'scraps');
    final targetDirectory = note.note == null
        ? path.join(_controller.vaultPath!, 'notes', note.folder)
        : path.dirname(note.note!.filePath);
    final body = scrap.body.replaceAllMapped(InlineImage.pattern, (match) {
      final uri = Uri.parse(match.group(2)!);
      if (uri.hasScheme) return match.group(0)!;
      final resolved = Uri.directory(
        sourceDirectory,
      ).resolveUri(uri).toFilePath();
      final relative = Uri(
        path: path
            .relative(resolved, from: targetDirectory)
            .replaceAll(r'\', '/'),
      ).toString();
      return match.group(0)!.replaceFirst(match.group(2)!, relative);
    });
    InlineImage.insert(_noteTextController, ScrapEmbed.wrap(scrap, body));
  }

  void _activateDocument(String sessionId) {
    if (!_saveInFlight) {
      _editorSession.activateDocument(sessionId);
    }
  }

  Future<void> _chooseVault() async {
    _localError = null;
    _UnsavedChoice? pendingChoice;
    if (_controller.hasVault &&
        (_editorSession.hasDirtyDocuments ||
            _noteController.hasDirtyDocuments)) {
      pendingChoice = await _askUnsavedChoice(
        title: 'Save changes before changing folders?',
        detail: 'Open scraps belong to the current local folder.',
      );
      if (pendingChoice == null || pendingChoice == _UnsavedChoice.cancel) {
        return;
      }
      if (pendingChoice == _UnsavedChoice.save &&
          !await _saveAllDirtyDocuments()) {
        return;
      }
    }

    await _persistRecovery();
    final selected = await _controller.chooseVault();
    if (!selected || !mounted) {
      return;
    }
    await _noteController.connect(_controller.vaultPath!);
    await _expenseController.connect(_controller.vaultPath!);

    if (_recoveryLoaded || pendingChoice != null) {
      _preparedVaultPath = _controller.vaultPath;
      await _discardAllDocuments();
      await _discardAllNotes();
      await _recoveryStore.clear();
      _editorSession.newDocument();
    } else {
      await _prepareEditorSession();
    }
    await _restoreNotesRecovery();
    await _restoreSyncStatus();
  }

  Future<void> _retryActiveScrapLocation() async {
    final scrap = _editorSession.activeDocument?.scrap;
    if (scrap == null) return;
    final updated = await _controller.captureLocationForScrap(scrap);
    if (updated != null && mounted) {
      _editorSession.refreshScrapMetadata(updated);
    }
  }

  Future<void> _setActiveScrapLocation(ScrapLocation location) async {
    final scrap = _editorSession.activeDocument?.scrap;
    if (scrap == null) return;
    final updated = await _controller.setLocationForScrap(scrap, location);
    if (updated != null && mounted) {
      _editorSession.refreshScrapMetadata(updated);
    }
  }

  Future<void> _chooseImages() async {
    if (_choosingImages || _syncInFlight) return;
    _choosingImages = true;
    _ensureActiveDocument();
    try {
      _addImagePaths(await _imagePathPicker());
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _localError = '이미지 선택기를 열지 못했습니다. $error');
      }
    } finally {
      _choosingImages = false;
    }
  }

  Future<bool> _pasteImage() async {
    if (_readingClipboard || _saveInFlight || _noteController.saving) {
      return true;
    }
    _readingClipboard = true;
    final section = _section;
    final session = section == ScrapnoteSection.notes
        ? _noteController.activeSessionId
        : _editorSession.activeSessionId;
    final textController = section == ScrapnoteSection.notes
        ? _noteTextController
        : _editorController;
    final selection = textController.selection;
    final body = textController.text;
    try {
      final imagePath = await _clipboardImageReader();
      if (imagePath == null) return false;
      if (!mounted) {
        await _deleteTemporaryImage(imagePath);
        return true;
      }
      final currentSession = section == ScrapnoteSection.notes
          ? _noteController.activeSessionId
          : _editorSession.activeSessionId;
      if (_section != section || currentSession != session) {
        await _deleteTemporaryImage(imagePath);
        return true;
      }
      if (textController.text == body && selection.isValid) {
        textController.selection = selection;
      }
      _temporaryImagePaths.add(imagePath);
      _addImagePaths(<String>[imagePath]);
      return true;
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _localError = '클립보드 이미지를 읽지 못했습니다. $error');
      }
      return true;
    } finally {
      _readingClipboard = false;
    }
  }

  void _addImagePaths(List<String> paths) {
    if (_saveInFlight || _noteController.saving) return;
    _ensureActiveDocument();
    var rejected = 0;
    for (final imagePath in paths) {
      if (!_imageExtensions.contains(path.extension(imagePath).toLowerCase())) {
        rejected += 1;
        continue;
      }
      final text = _section == ScrapnoteSection.notes
          ? _noteTextController
          : _editorController;
      InlineImage.insert(
        text,
        InlineImage.markdown(imagePath, label: path.basename(imagePath)),
      );
      if (_section == ScrapnoteSection.notes) {
        _noteController.addAttachment(imagePath);
      } else {
        _editorSession.addActiveAttachment(imagePath);
      }
    }
    if (rejected > 0 && mounted) {
      setState(() => _localError = '이미지 파일만 첨부할 수 있습니다.');
    }
  }

  void _removeImage(String imagePath) {
    if (_section == ScrapnoteSection.notes) {
      _noteController.removeAttachment(imagePath);
    } else {
      _editorSession.removeActiveAttachment(imagePath);
    }
    if (_temporaryImagePaths.remove(imagePath)) {
      unawaited(_deleteTemporaryImage(imagePath));
    }
  }

  void _ensureActiveDocument() {
    if (_section == ScrapnoteSection.notes) {
      if (_noteController.activeDocument == null) {
        _noteController.newDocument();
      }
    } else if (_editorSession.activeDocument == null) {
      _editorSession.newDocument();
    }
  }

  Future<bool> _saveActiveDocument() async {
    final document = _editorSession.activeDocument;
    if (document == null || _saveInFlight) {
      return document != null;
    }
    if (!document.dirty) {
      return true;
    }

    setState(() {
      _saveInFlight = true;
      _localError = null;
    });
    final attachments = List<String>.of(document.pendingImagePaths);
    try {
      final saved = await _controller.saveDocument(
        document.body,
        existing: document.scrap,
        attachmentPaths: attachments,
      );
      if (saved == null || !mounted) {
        return false;
      }
      if (_editorSession.activeSessionId != document.sessionId) {
        _editorSession.activateDocument(document.sessionId);
      }
      _editorSession.markSaved(saved);
      for (final imagePath in attachments) {
        if (_temporaryImagePaths.remove(imagePath)) {
          await _deleteTemporaryImage(imagePath);
        }
      }
      return true;
    } finally {
      if (mounted) {
        setState(() => _saveInFlight = false);
      }
    }
  }

  Future<void> _requestCloseTab(String sessionId) async {
    if (_saveInFlight) {
      return;
    }
    final document = _documentFor(sessionId);
    if (document == null) {
      return;
    }
    if (!document.dirty) {
      _editorSession.closeDocument(sessionId);
      return;
    }

    _editorSession.activateDocument(sessionId);
    final choice = await _askUnsavedChoice(
      title: 'Save changes to “${document.displayName}”?',
      detail: 'Your changes will be lost if you don’t save them.',
    );
    switch (choice) {
      case _UnsavedChoice.save:
        if (await _saveActiveDocument()) {
          _editorSession.closeDocument(sessionId);
        }
      case _UnsavedChoice.discard:
        await _discardDocument(document);
      case _UnsavedChoice.cancel || null:
        return;
    }
  }

  Future<bool> _saveActiveNote() async {
    final active = _noteController.activeDocument;
    if (active == null) return false;
    final temporaryPaths = List<String>.of(active.pendingImagePaths);
    final saved = await _noteController.saveActive();
    if (saved) {
      for (final imagePath in temporaryPaths) {
        if (_temporaryImagePaths.remove(imagePath)) {
          await _deleteTemporaryImage(imagePath);
        }
      }
    }
    return saved;
  }

  Future<void> _closeActiveDocument() async {
    if (_section == ScrapnoteSection.notes) {
      final sessionId = _noteController.activeSessionId;
      if (sessionId != null) await _requestCloseNoteTab(sessionId);
      return;
    }
    if (_section == ScrapnoteSection.scraps) {
      final sessionId = _editorSession.activeSessionId;
      if (sessionId != null) await _requestCloseTab(sessionId);
    }
  }

  Future<void> _requestCloseNoteTab(String sessionId) async {
    final document = _noteController.documents
        .where((candidate) => candidate.sessionId == sessionId)
        .firstOrNull;
    if (document == null) return;
    if (!document.dirty) {
      _noteController.close(sessionId);
      return;
    }
    _noteController.activate(sessionId);
    final choice = await _askUnsavedChoice(
      title: 'Save changes to “${document.title}”?',
      detail: 'Your changes will be lost if you don’t save them.',
    );
    switch (choice) {
      case _UnsavedChoice.save:
        if (await _saveActiveNote()) _noteController.close(sessionId);
      case _UnsavedChoice.discard:
        await _discardNote(document);
      case _UnsavedChoice.cancel || null:
        return;
    }
  }

  Future<void> _createNoteFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const FolderNameDialog(),
    );
    if (!mounted) return;
    if (name != null && name.trim().isNotEmpty) {
      await _noteController.createFolder(name);
    }
  }

  List<String> _scrapImagePaths(EditorDocument? document) {
    final scrap = document?.scrap;
    final vaultPath = _controller.vaultPath;
    if (scrap == null || vaultPath == null) return const <String>[];
    return scrap.assets
        .map(
          (asset) => path.normalize(
            path.join(vaultPath, 'scraps', asset.relativePath),
          ),
        )
        .toList(growable: false);
  }

  Future<bool> _handleWindowCloseRequest() async {
    if (_syncInFlight) return false;
    if (!mounted ||
        (!_editorSession.hasDirtyDocuments &&
            !_noteController.hasDirtyDocuments)) {
      return true;
    }
    final dirtyCount =
        _editorSession.documents.where((document) => document.dirty).length +
        _noteController.documents.where((document) => document.dirty).length;
    final choice = await _askUnsavedChoice(
      title: dirtyCount == 1
          ? 'Save the open change?'
          : 'Save $dirtyCount open changes?',
      detail: 'Unsaved changes are not yet in your local folder.',
    );
    switch (choice) {
      case _UnsavedChoice.save:
        final saved = await _saveAllDirtyDocuments();
        if (saved) {
          await _recoveryStore.clear();
        }
        return saved;
      case _UnsavedChoice.discard:
        await _discardAllDocuments();
        await _discardAllNotes();
        await _recoveryStore.clear();
        return true;
      case _UnsavedChoice.cancel || null:
        return false;
    }
  }

  Future<bool> _saveAllDirtyDocuments() async {
    final dirtyIds = _editorSession.documents
        .where((document) => document.dirty)
        .map((document) => document.sessionId)
        .toList(growable: false);
    for (final sessionId in dirtyIds) {
      _editorSession.activateDocument(sessionId);
      if (!await _saveActiveDocument()) {
        return false;
      }
    }
    final dirtyNoteIds = _noteController.documents
        .where((document) => document.dirty)
        .map((document) => document.sessionId)
        .toList(growable: false);
    for (final sessionId in dirtyNoteIds) {
      _noteController.activate(sessionId);
      if (!await _saveActiveNote()) return false;
    }
    return true;
  }

  Future<void> _discardAllDocuments() async {
    final documents = List<EditorDocument>.of(_editorSession.documents);
    for (final document in documents) {
      await _discardDocument(document);
    }
  }

  Future<void> _discardDocument(EditorDocument document) async {
    for (final imagePath in document.pendingImagePaths) {
      if (_temporaryImagePaths.remove(imagePath)) {
        await _deleteTemporaryImage(imagePath);
      }
    }
    _editorSession.discardDocument(document.sessionId);
  }

  Future<void> _discardAllNotes() async {
    final documents = List<NoteEditorDocument>.of(_noteController.documents);
    for (final document in documents) {
      await _discardNote(document);
    }
  }

  Future<void> _discardNote(NoteEditorDocument document) async {
    for (final imagePath in document.pendingImagePaths) {
      if (_temporaryImagePaths.remove(imagePath)) {
        await _deleteTemporaryImage(imagePath);
      }
    }
    _noteController.discard(document.sessionId);
  }

  EditorDocument? _documentFor(String sessionId) {
    for (final document in _editorSession.documents) {
      if (document.sessionId == sessionId) {
        return document;
      }
    }
    return null;
  }

  Future<_UnsavedChoice?> _askUnsavedChoice({
    required String title,
    required String detail,
  }) {
    return showDialog<_UnsavedChoice>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ScrapnoteTokens.paperRaised,
        surfaceTintColor: ScrapnoteTokens.transparent,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: ScrapnoteTokens.rule),
          borderRadius: BorderRadius.circular(ScrapnoteTokens.radiusLarge),
        ),
        title: Text(title),
        content: Text(detail),
        actions: <Widget>[
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnsavedChoice.cancel),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnsavedChoice.discard),
            child: const Text('Don’t Save'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnsavedChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _dismissError() {
    setState(() => _localError = null);
    _controller.clearError();
    _noteController.clearError();
  }

  static Future<List<String>> _pickImageFiles() async {
    const images = XTypeGroup(
      label: 'Images',
      extensions: <String>[
        'bmp',
        'gif',
        'heic',
        'heif',
        'jpeg',
        'jpg',
        'png',
        'tif',
        'tiff',
        'webp',
      ],
      mimeTypes: <String>['image/*'],
      uniformTypeIdentifiers: <String>['public.image'],
      webWildCards: <String>['image/*'],
    );
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[images],
      confirmButtonText: 'Add images',
    );
    return files.map((file) => file.path).toList(growable: false);
  }

  static Future<void> _deleteTemporaryImage(String imagePath) async {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _formatSyncTime(DateTime value) {
    String two(int component) => component.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

enum _UnsavedChoice { save, discard, cancel }

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ScrapnoteTokens.paperSunken,
      padding: const EdgeInsets.fromLTRB(
        ScrapnoteTokens.space4,
        ScrapnoteTokens.space2,
        ScrapnoteTokens.space2,
        ScrapnoteTokens.space2,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            FLucideIcons.triangleAlert,
            size: 15,
            color: ScrapnoteTokens.destructive,
          ),
          const SizedBox(width: ScrapnoteTokens.space3),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ScrapnoteTokens.charcoalSoft,
                fontSize: 12,
              ),
            ),
          ),
          FButton.icon(
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.sm,
            semanticsLabel: 'Dismiss error',
            onPress: onDismiss,
            child: const Icon(FLucideIcons.x, size: 14),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusLine extends StatelessWidget {
  const _SyncStatusLine({
    required this.status,
    required this.syncing,
    required this.onSync,
  });

  final String status;
  final bool syncing;
  final VoidCallback? onSync;

  bool get _failed => status.contains('못했습니다') || status.contains('충돌');
  bool get _complete => status.contains('완료') || status.contains('마지막 동기화');

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: status,
      child: SizedBox(
        key: const ValueKey<String>('sync-status-line'),
        height: ScrapnoteTokens.minimumHitTarget,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: ScrapnoteTokens.paperRaised,
            border: Border(top: BorderSide(color: ScrapnoteTokens.rule)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ScrapnoteTokens.space3,
            ),
            child: Row(
              children: <Widget>[
                if (syncing)
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
                  Icon(
                    _failed
                        ? FLucideIcons.cloudAlert
                        : _complete
                        ? FLucideIcons.cloudCheck
                        : FLucideIcons.cloud,
                    size: 13,
                    color: _failed
                        ? ScrapnoteTokens.destructive
                        : _complete
                        ? ScrapnoteTokens.success
                        : ScrapnoteTokens.mutedInk,
                  ),
                const SizedBox(width: ScrapnoteTokens.space2),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ScrapnoteTokens.mutedInk,
                      fontSize: 11,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: ScrapnoteTokens.space2),
                FButton(
                  key: const ValueKey<String>('manual-sync-button'),
                  variant: FButtonVariant.ghost,
                  onPress: syncing ? null : onSync,
                  prefix: const Icon(FLucideIcons.refreshCw, size: 14),
                  child: Text(syncing ? '동기화 중…' : '동기화', maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
