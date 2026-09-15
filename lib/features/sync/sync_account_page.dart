import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/scrapnote_theme.dart';
import '../../infrastructure/sync/sync_manifest.dart';
import '../../infrastructure/sync/sync_bootstrap.dart';

class SyncAccountPage extends StatefulWidget {
  const SyncAccountPage({
    required this.client,
    required this.onSync,
    required this.status,
    super.key,
  });
  final SupabaseClient client;
  final Future<String> Function(Map<String, SyncResolution>) onSync;
  final String status;
  @override
  State<SyncAccountPage> createState() => _SyncAccountPageState();
}

class _SyncAccountPageState extends State<SyncAccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  StreamSubscription<AuthState>? _authSubscription;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  bool _busy = false;
  late String _status = widget.status;
  List<SyncConflict> _conflicts = [];
  final _resolutions = <String, SyncResolution>{};

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _authSubscription?.cancel();
    _resendTimer?.cancel();
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
    } on AuthException catch (error) {
      _status = _authErrorMessage(error);
    } on Exception {
      _status = '연결하지 못했습니다. 인터넷 연결과 계정 상태를 확인한 뒤 다시 시도해 주세요. 기기의 파일은 유지됩니다.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _checkEmail() {
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      return true;
    }
    setState(() => _status = '가입한 이메일 주소를 입력해 주세요.');
    return false;
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    _resendSeconds = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendSeconds--);
      if (_resendSeconds == 0) timer.cancel();
    });
  }

  Future<void> _resendConfirmation() async {
    if (!_checkEmail() || _resendSeconds > 0) return;
    await _run(() async {
      await widget.client.auth.resend(
        type: OtpType.signup,
        email: _email.text.trim(),
        emailRedirectTo: SyncBootstrap.authRedirectUrl,
      );
      _startResendCooldown();
      _status =
          '인증 메일을 요청했습니다. 가장 최근 메일의 링크를 열어 주세요. 이미 인증했다면 비밀번호로 로그인할 수 있습니다.';
    });
  }

  String _authErrorMessage(AuthException error) => switch (error.code) {
    'email_not_confirmed' => '이메일 인증이 필요합니다. 아래에서 인증 메일을 다시 받을 수 있습니다.',
    'otp_expired' =>
      '인증 링크가 이미 사용되었거나 만료되었습니다. 먼저 로그인을 시도하고, 인증이 필요하면 메일을 다시 받아 주세요.',
    'over_email_send_rate_limit' ||
    'over_request_rate_limit' => '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.',
    'invalid_credentials' => '이메일 또는 비밀번호가 맞지 않습니다. 입력 내용을 확인해 주세요.',
    'flow_state_not_found' || 'flow_state_expired' || 'bad_code_verifier' =>
      '이메일을 확인했다면 가입한 비밀번호로 로그인해 주세요. 인증 링크는 가입을 시작한 기기에서 열어 주세요.',
    _ => error.message,
  };

  @override
  void initState() {
    super.initState();
    _authSubscription = widget.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        setState(() {
          if (state.event == AuthChangeEvent.signedIn) {
            _password.clear();
            _status = '로그인했습니다. 저장하고 동기화를 눌러 기기의 파일을 연결하세요.';
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(
          () => _status = error is AuthException
              ? _authErrorMessage(error)
              : '인증 결과를 확인하지 못했습니다. 가입한 비밀번호로 로그인을 시도해 주세요.',
        );
      },
    );
  }

  Future<void> _sync() => _run(() async {
    _status = await widget.onSync(_resolutions);
    _conflicts = [];
    _resolutions.clear();
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
                    const Text(
                      '모든 기기에서 이어 쓰기',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '노트, 스크랩, 이미지와 가계부를 개인 계정으로 연동합니다. 오프라인에서는 기기에 저장하고, 앱을 다시 열거나 저장한 뒤 동기화합니다.',
                    ),
                    const SizedBox(height: 24),
                    if (user == null) ...[
                      FTextField(
                        label: const Text('이메일'),
                        control: FTextFieldControl.managed(controller: _email),
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 16),
                      FTextField.password(
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
                                    await widget.client.auth.signInWithPassword(
                                      email: _email.text.trim(),
                                      password: _password.text,
                                    );
                                    _password.clear();
                                    _status =
                                        '로그인했습니다. 동기화를 누르면 현재 기기의 저장된 파일을 연결합니다.';
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
                            : () {
                                if (!_checkEmail()) return;
                                unawaited(
                                  _run(() async {
                                    final response = await widget.client.auth
                                        .signUp(
                                          emailRedirectTo:
                                              SyncBootstrap.authRedirectUrl,
                                          email: _email.text.trim(),
                                          password: _password.text,
                                        );
                                    _password.clear();
                                    if (response.session == null) {
                                      _startResendCooldown();
                                    }
                                    _status = response.session == null
                                        ? '가장 최근 인증 메일의 링크를 이 기기에서 열어 주세요. Scrapnote로 돌아와 로그인을 마칠 수 있습니다. 이미 인증했다면 비밀번호로 로그인하세요.'
                                        : '로그인했습니다. 저장하고 동기화를 눌러 주세요.';
                                  }),
                                );
                              },
                        child: const Text('계정 만들기'),
                      ),
                      const SizedBox(height: 12),
                      FButton(
                        variant: FButtonVariant.ghost,
                        onPress: _busy || _resendSeconds > 0
                            ? null
                            : _resendConfirmation,
                        child: Text(
                          _resendSeconds > 0
                              ? '$_resendSeconds초 후 재발송'
                              : '인증 메일 다시 받기',
                        ),
                      ),
                    ] else ...[
                      Text(user.email ?? '로그인됨'),
                      const SizedBox(height: 16),
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
                              ? '저장하고 동기화'
                              : '선택한 내용으로 동기화',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FButton(
                        variant: FButtonVariant.ghost,
                        onPress: _busy
                            ? null
                            : () => _run(() async {
                                await widget.client.auth.signOut(
                                  scope: SignOutScope.local,
                                );
                                _conflicts = [];
                                _resolutions.clear();
                                _status =
                                    '이 기기에서 로그아웃했습니다. 기기에 저장된 파일은 남아 있습니다.';
                              }),
                        child: const Text('이 기기에서 로그아웃'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Semantics(liveRegion: true, child: Text(_status)),
                    for (final conflict in _conflicts) ...[
                      const Divider(height: 32),
                      Text(conflict.path),
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
}
