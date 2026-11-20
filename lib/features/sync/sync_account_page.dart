// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:scrapnote/infrastructure/sync/sync_client.dart';

import '../../app/scrapnote_theme.dart';
import '../../infrastructure/sync/sync_manifest.dart';
import '../../infrastructure/sync/sync_vault_summary.dart';
import '../../infrastructure/sync/capture_sync_engine.dart';
import '../../core/design/scrapnote_tokens.dart';

class SyncAccountPage extends StatefulWidget {
  const SyncAccountPage({
    required this.client,
    required this.onSync,
    required this.status,
    required this.vaultPath,
    this.summaryLoader = loadSyncVaultSummary,
    this.captureOnly = false,
    this.onSignedIn,
    super.key,
  });
  final SyncClient client;
  final Future<String> Function(Map<String, SyncResolution>) onSync;
  final String status;
  final String vaultPath;
  final SyncVaultSummaryLoader summaryLoader;
  final bool captureOnly;
  final Future<String> Function()? onSignedIn;
  @override
  State<SyncAccountPage> createState() => _SyncAccountPageState();
}

class _SyncAccountPageState extends State<SyncAccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _resetCode = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _resettingPassword = false;
  bool _resetCodeSent = false;
  StreamSubscription<SyncAuthState>? _authSubscription;
  bool _busy = false;
  late String _status = widget.status;
  List<SyncConflict> _conflicts = [];
  final _resolutions = <String, SyncResolution>{};
  SyncVaultSummary _summary = SyncVaultSummary.empty;
  bool _summaryLoading = true;
  String? _summaryError;
  List<CaptureItem> _captureItems = [];
  String? _migrationNotice;
  final Map<String, List<String>> _capturePreviews = {};

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _resetCode.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on SyncConflicts catch (error) {
      _conflicts = error.files;
      _resolutions.clear();
      _status =
          '같은 파일이 양쪽에서 바뀌었습니다. 사용할 내용을 선택해 주세요. 삭제와 수정이 겹친 경우도 여기에 표시됩니다.';
      if (widget.captureOnly) {
        await _loadSummary();
        for (final conflict in _conflicts) {
          try {
            final previews = <String>[];
            for (final digest in [conflict.local, conflict.remote]) {
              if (digest == null) {
                previews.add('삭제됨');
                continue;
              }
              final bytes = digest == conflict.local
                  ? await (await CaptureSyncEngine.safeFile(
                      Directory(widget.vaultPath),
                      conflict.path,
                    )).readAsBytes()
                  : await widget.client.request('GET', '/v1/blobs/$digest');
              final body = CaptureSyncEngine.codec
                  .decode(utf8.decode(bytes))
                  .body;
              previews.add(
                body.length > 1200 ? '${body.substring(0, 1200)}…' : body,
              );
            }
            _capturePreviews[conflict.path] = previews;
          } on Exception {
            /* The conflict remains resolvable without a preview. */
          }
        }
      }
    } on SyncAuthException catch (error) {
      _status = _authErrorMessage(error);
    } on Exception {
      _status = '연결하지 못했습니다. 인터넷 연결과 계정 상태를 확인한 뒤 다시 시도해 주세요. 기기의 파일은 유지됩니다.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSummary() async {
    if (mounted) {
      setState(() {
        _summaryLoading = true;
        _summaryError = null;
      });
    }
    try {
      final summary = widget.captureOnly
          ? SyncVaultSummary.empty
          : await widget.summaryLoader(widget.vaultPath);
      final captureItems = widget.captureOnly
          ? await CaptureSyncEngine.items(Directory(widget.vaultPath))
          : <CaptureItem>[];
      final captureState = widget.captureOnly
          ? await CaptureSyncEngine.readState(Directory(widget.vaultPath))
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _captureItems = captureItems;
        _migrationNotice = captureState['migration_notice'] as String?;
      });
    } on FileSystemException {
      if (!mounted) return;
      setState(() => _summaryError = 'Vault 통계를 읽지 못했습니다. 폴더 접근 권한을 확인해 주세요.');
    } on FormatException {
      if (mounted) {
        setState(() => _summaryError = '전송 내역을 읽지 못했습니다. 기기에 저장된 파일은 유지됩니다.');
      }
    } finally {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  bool _checkEmail() {
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      return true;
    }
    setState(() => _status = '가입한 이메일 주소를 입력해 주세요.');
    return false;
  }

  void _clearPasswordFields() {
    _resetCodeSent = false;
    _resetCode.clear();
    _newPassword.clear();
    _confirmPassword.clear();
  }

  void _requestPasswordReset() {
    if (!_checkEmail()) return;
    unawaited(
      _run(() async {
        await widget.client.auth.requestPasswordReset(
          email: _email.text.trim(),
        );
        _resetCode.clear();
        _resetCodeSent = true;
        _status =
            '등록된 주소로 재설정 코드를 요청했습니다. 메일함을 확인해 주세요. 코드는 15분 동안 유효하며, 재요청은 1분 뒤에 해 주세요.';
      }),
    );
  }

  void _resetPassword() {
    if (!_checkEmail()) return;
    if (_resetCode.text.trim().isEmpty) {
      setState(() => _status = '이메일로 받은 재설정 코드를 입력해 주세요.');
      return;
    }
    if (_newPassword.text.length < 16 || _newPassword.text.length > 1024) {
      setState(() => _status = '새 비밀번호는 16자 이상 1024자 이하여야 합니다.');
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _status = '새 비밀번호가 일치하지 않습니다.');
      return;
    }
    unawaited(
      _run(() async {
        await widget.client.auth.resetPassword(
          email: _email.text.trim(),
          code: _resetCode.text.trim(),
          newPassword: _newPassword.text,
        );
        _clearPasswordFields();
        _password.clear();
        _resettingPassword = false;
        _status = '비밀번호를 변경했습니다. 새 비밀번호로 로그인해 주세요.';
      }),
    );
  }

  String _authErrorMessage(SyncAuthException error) => error.message;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSummary());
    _authSubscription = widget.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        final signedIn = state.event == SyncAuthEvent.signedIn;
        setState(() {
          if (signedIn) {
            _password.clear();
            _clearPasswordFields();
            _resettingPassword = false;
            _status = widget.captureOnly
                ? '로그인했습니다. 이 휴대폰의 Scrap만 업로드합니다.'
                : '로그인했습니다. 저장하고 동기화를 눌러 기기의 파일을 연결하세요.';
          }
        });
        if (signedIn) unawaited(_loadSummary());
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(
          () => _status = error is SyncAuthException
              ? _authErrorMessage(error)
              : '인증 결과를 확인하지 못했습니다. 가입한 비밀번호로 로그인을 시도해 주세요.',
        );
      },
    );
  }

  Future<void> _sync() => _run(() async {
    _status = widget.captureOnly
        ? '이 휴대폰의 Scrap을 저장하고 전송하는 중입니다.'
        : '기기의 변경 내용을 저장하고 동기화하는 중입니다.';
    _status = await widget.onSync(_resolutions);
    _conflicts = [];
    _resolutions.clear();
    await _loadSummary();
  });

  @override
  Widget build(BuildContext context) {
    final user = widget.client.auth.currentUser;
    return FTheme(
      data: ScrapnoteTheme.forContext(context),
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('계정 및 동기화'),
            automaticallyImplyLeading: !_busy,
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      widget.captureOnly ? '내 Scrap 업로드' : '모든 기기에서 이어 쓰기',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.captureOnly
                          ? '이 휴대폰에서 작성한 Scrap과 첨부만 전송합니다. 저장한 내용은 앱이 열려 있을 때 자동으로 전송하며, 수정·삭제도 서버에 반영합니다.'
                          : '노트, 스크랩, 이미지와 가계부를 개인 계정으로 연동합니다. 기기에 저장된 내용을 동기화 버튼을 눌렀을 때만 다른 기기와 연결합니다.',
                    ),
                    const SizedBox(height: 24),
                    if (_migrationNotice != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(_migrationNotice!),
                      ),
                    if (user == null) ...[
                      FTextField(
                        label: const Text('이메일'),
                        control: FTextFieldControl.managed(controller: _email),
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_busy && !_resetCodeSent,
                      ),
                      const SizedBox(height: 16),
                      if (_resettingPassword) ...[
                        const Text('가입한 이메일로 받은 코드로 본인 확인 후 비밀번호를 재설정합니다.'),
                        const SizedBox(height: 16),
                        if (_resetCodeSent) ...[
                          const Text('재설정하면 모든 기기에서 로그아웃됩니다.'),
                          const SizedBox(height: 12),
                          FTextField(
                            key: const ValueKey('reset-code'),
                            label: const Text('재설정 코드'),
                            control: FTextFieldControl.managed(
                              controller: _resetCode,
                            ),
                            enabled: !_busy,
                          ),
                          const SizedBox(height: 12),
                          FTextField.password(
                            key: const ValueKey('new-password'),
                            label: const Text('새 비밀번호 (16자 이상)'),
                            control: FTextFieldControl.managed(
                              controller: _newPassword,
                            ),
                            enabled: !_busy,
                          ),
                          const SizedBox(height: 12),
                          FTextField.password(
                            key: const ValueKey('confirm-password'),
                            label: const Text('새 비밀번호 확인'),
                            control: FTextFieldControl.managed(
                              controller: _confirmPassword,
                            ),
                            enabled: !_busy,
                          ),
                          const SizedBox(height: 12),
                          FButton(
                            onPress: _busy ? null : _resetPassword,
                            child: const Text('새 비밀번호 저장'),
                          ),
                          const SizedBox(height: 8),
                          FButton(
                            variant: FButtonVariant.outline,
                            onPress: _busy ? null : _requestPasswordReset,
                            child: const Text('코드 다시 받기'),
                          ),
                        ] else
                          FButton(
                            onPress: _busy ? null : _requestPasswordReset,
                            child: const Text('재설정 코드 받기'),
                          ),
                        const SizedBox(height: 8),
                        FButton(
                          variant: FButtonVariant.outline,
                          onPress: _busy
                              ? null
                              : () => setState(() {
                                  _clearPasswordFields();
                                  _resettingPassword = false;
                                  _status = '';
                                }),
                          child: const Text('로그인으로 돌아가기'),
                        ),
                      ] else ...[
                        FTextField.password(
                          key: const ValueKey('login-password'),
                          label: const Text('비밀번호'),
                          control: FTextFieldControl.managed(
                            controller: _password,
                          ),
                          enabled: !_busy,
                        ),
                        const SizedBox(height: 24),
                        FButton(
                          onPress: _busy
                              ? null
                              : () {
                                  if (!_checkEmail()) return;
                                  unawaited(
                                    _run(() async {
                                      await widget.client.auth
                                          .signInWithPassword(
                                            email: _email.text.trim(),
                                            password: _password.text,
                                          );
                                      _password.clear();
                                      if (widget.captureOnly) {
                                        _status =
                                            await widget.onSignedIn?.call() ??
                                            '로그인했습니다. 저장된 Scrap을 전송할 수 있습니다.';
                                        await _loadSummary();
                                      } else {
                                        _status =
                                            '로그인했습니다. 동기화를 누르면 현재 기기의 저장된 파일을 연결합니다.';
                                      }
                                    }),
                                  );
                                },
                          child: const Text('로그인'),
                        ),
                        const SizedBox(height: 12),
                        FButton(
                          variant: FButtonVariant.outline,
                          onPress: _busy
                              ? null
                              : () => setState(() {
                                  _password.clear();
                                  _clearPasswordFields();
                                  _resettingPassword = true;
                                  _status = '';
                                }),
                          child: const Text('비밀번호 재설정'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text('개인 서버에 등록된 계정으로 로그인하세요.'),
                    ] else ...[
                      _SectionHeading(
                        icon: FLucideIcons.userRound,
                        title: '로그인 세션',
                      ),
                      _DetailRow(label: '이메일', value: user.email),
                      _DetailRow(label: '로그인 방식', value: '이메일 · 개인 서버'),
                      _DetailRow(
                        label: '계정 생성',
                        value: _dateString(user.createdAt),
                      ),
                      _DetailRow(
                        label: '최근 로그인',
                        value: _dateString(user.lastSignInAt),
                      ),
                      _DetailRow(
                        label: '세션 만료 예정',
                        value: _sessionExpiry(
                          widget.client.auth.currentSession,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionHeading(
                        icon: FLucideIcons.folderSync,
                        title: widget.captureOnly
                            ? '이 휴대폰의 작성·전송 내역'
                            : '이 Vault의 동기화 범위',
                      ),
                      if (_summaryLoading)
                        const LinearProgressIndicator(minHeight: 2)
                      else if (_summaryError case final error?)
                        Text(
                          error,
                          style: const TextStyle(
                            color: ScrapnoteTokens.destructive,
                            fontSize: 13,
                          ),
                        )
                      else if (widget.captureOnly) ...[
                        Text(
                          '작성한 Scrap ${_captureItems.where((item) => !item.deleted).length}개 · 전송 확인 필요 ${_captureItems.where((item) => item.phase != CapturePhase.complete).length}개',
                        ),
                        const SizedBox(height: 12),
                        if (_captureItems.isEmpty)
                          const Text('아직 이 휴대폰에서 저장한 Scrap이 없습니다.'),
                        for (final item in _captureItems)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  item.label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ScrapnoteTokens.mutedInk,
                                  ),
                                ),
                                if (item.error != null)
                                  Text(
                                    item.error!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: ScrapnoteTokens.destructive,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ] else ...[
                        _CountGrid(summary: _summary),
                        const SizedBox(height: 12),
                        _DetailRow(
                          label: '동기화 대상',
                          value:
                              '${_summary.fileCount}개 파일 · ${_formatBytes(_summary.totalBytes)}',
                        ),
                        _DetailRow(
                          label: '지난 동기화 항목',
                          value: '${_summary.syncedItemCount}개 파일',
                        ),
                        _DetailRow(
                          label: '마지막 성공',
                          value: _summary.lastSyncedAt == null
                              ? '아직 없음'
                              : _date(_summary.lastSyncedAt!.toLocal()),
                        ),
                        const Text(
                          '항목 수와 용량은 현재 기기의 파일 기준입니다. 서버에 저장된 전체 자료 수가 아닙니다.',
                          style: TextStyle(
                            color: ScrapnoteTokens.mutedInk,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_busy) const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 8),
                      FButton(
                        onPress:
                            _busy ||
                                (_conflicts.isNotEmpty &&
                                    _resolutions.length != _conflicts.length)
                            ? null
                            : _sync,
                        prefix: const Icon(FLucideIcons.refreshCw),
                        child: Text(
                          _busy
                              ? '동기화 중…'
                              : _conflicts.isEmpty
                              ? widget.captureOnly
                                    ? '저장하고 업로드'
                                    : '저장하고 동기화'
                              : '선택한 내용으로 동기화',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FButton(
                        variant: FButtonVariant.outline,
                        onPress: _busy
                            ? null
                            : () => _run(() async {
                                await widget.client.auth.signOut();
                                _clearPasswordFields();
                                _resettingPassword = false;
                                _conflicts = [];
                                _resolutions.clear();
                                _status =
                                    '이 기기에서 로그아웃했습니다. 기기에 저장된 파일은 남아 있습니다.';
                              }),
                        prefix: const Icon(FLucideIcons.logOut),
                        child: const Text('이 기기에서 로그아웃'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Semantics(liveRegion: true, child: Text(_status)),
                    for (final conflict in _conflicts) ...[
                      const Divider(height: 32),
                      Text(
                        widget.captureOnly
                            ? _captureItems
                                      .where(
                                        (item) => item.path == conflict.path,
                                      )
                                      .firstOrNull
                                      ?.title ??
                                  'Scrap'
                            : conflict.path,
                      ),
                      if (_capturePreviews[conflict.path] case final previews?)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('이 기기'),
                              Text(previews[0]),
                              const SizedBox(height: 12),
                              const Text('서버'),
                              Text(previews[1]),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final local in [true, false])
                            FButton(
                              mainAxisSize: MainAxisSize.min,
                              variant:
                                  _resolutions[conflict.path]?.useLocal == local
                                  ? FButtonVariant.primary
                                  : FButtonVariant.outline,
                              onPress: _busy
                                  ? null
                                  : () => setState(
                                      () => _resolutions[conflict.path] =
                                          SyncResolution(
                                            conflict,
                                            useLocal: local,
                                          ),
                                    ),
                              child: Text(
                                '${local ? '이 기기' : '서버'}${(local ? conflict.local : conflict.remote) == null ? '에서 삭제됨' : ' 내용 사용'}',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _sessionExpiry(SyncSession? session) =>
      session == null ? '확인할 수 없음' : _date(session.expiresAt.toLocal());

  static String _dateString(String? value) {
    final parsed = value == null ? null : DateTime.tryParse(value);
    return parsed == null ? '기록 없음' : _date(parsed.toLocal());
  }

  static String _date(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm').format(value);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KB';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MB';
    final gib = mib / 1024;
    return '${gib.toStringAsFixed(gib < 10 ? 1 : 0)} GB';
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ScrapnoteTokens.space3),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: ScrapnoteTokens.charcoalSoft),
          const SizedBox(width: ScrapnoteTokens.space2),
          Text(
            title,
            style: const TextStyle(
              color: ScrapnoteTokens.charcoal,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ScrapnoteTokens.rule)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: ScrapnoteTokens.mutedInk,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ScrapnoteTokens.charcoal,
                fontFamily: 'monospace',
                fontSize: 12,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountGrid extends StatelessWidget {
  const _CountGrid({required this.summary});

  final SyncVaultSummary summary;

  @override
  Widget build(BuildContext context) {
    final values = <(String, int)>[
      ('Scrap', summary.scrapCount),
      ('Note', summary.noteCount),
      ('첨부', summary.assetCount),
      ('지출', summary.expenseCount),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - ScrapnoteTokens.hairline) / 2;
        return Wrap(
          spacing: ScrapnoteTokens.hairline,
          runSpacing: ScrapnoteTokens.hairline,
          children: <Widget>[
            for (final value in values)
              Container(
                width: width,
                height: 58,
                padding: const EdgeInsets.symmetric(
                  horizontal: ScrapnoteTokens.space3,
                  vertical: ScrapnoteTokens.space2,
                ),
                color: ScrapnoteTokens.paperSunken,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      value.$1,
                      style: const TextStyle(
                        color: ScrapnoteTokens.mutedInk,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${value.$2}',
                      style: const TextStyle(
                        color: ScrapnoteTokens.charcoal,
                        fontFamily: 'monospace',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
