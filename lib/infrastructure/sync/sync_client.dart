import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class SyncAuthException implements Exception {
  const SyncAuthException(this.message, {this.code});
  final String message;
  final String? code;
}

class SyncUser {
  SyncUser.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      email = json['email'] as String,
      createdAt = json['created_at'] as String?,
      lastSignInAt = json['last_sign_in_at'] as String?;
  final String id;
  final String email;
  final String? createdAt;
  final String? lastSignInAt;
}

class SyncSession {
  SyncSession.fromJson(this.json)
    : accessToken = json['access_token'] as String,
      expiresAt = DateTime.parse(json['expires_at'] as String),
      user = SyncUser.fromJson(json['user'] as Map<String, dynamic>);
  final Map<String, dynamic> json;
  final String accessToken;
  final DateTime expiresAt;
  final SyncUser user;
}

enum SyncAuthEvent { signedIn, signedOut }

class SyncAuthState {
  const SyncAuthState(this.event);
  final SyncAuthEvent event;
}

abstract interface class SyncSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SyncClient {
  SyncClient(
    String url, {
    http.Client? httpClient,
    SyncSessionStore? sessionStore,
  }) : baseUri = Uri.parse(
         url.endsWith('/') ? url.substring(0, url.length - 1) : url,
       ),
       _http = httpClient ?? http.Client() {
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.path.isNotEmpty && baseUri.path != '/')) {
      throw const FormatException('동기화 서버는 HTTPS 주소여야 합니다.');
    }
    auth = SyncAuth(this, sessionStore);
  }
  final Uri baseUri;
  final http.Client _http;
  late final SyncAuth auth;
  String get serverUrl => baseUri.toString();

  Future<Uint8List> request(
    String method,
    String path, {
    Object? jsonBody,
    Uint8List? bytes,
    Map<String, String>? query,
    bool authenticated = true,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final request = http.Request(
      method,
      baseUri.replace(path: path, queryParameters: query),
    )..followRedirects = false;
    final session = auth.currentSession;
    if (authenticated) {
      if (session == null || !session.expiresAt.isAfter(DateTime.now())) {
        await auth.clear();
        throw const SyncAuthException('다시 로그인해 주세요.', code: 'unauthorized');
      }
      request.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    } else if (bytes != null) {
      request.headers['Content-Type'] = 'application/octet-stream';
      request.bodyBytes = bytes;
    }
    final response = await _http.send(request).timeout(timeout);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(timeout)) {
      builder.add(chunk);
      if (builder.length > 25 * 1024 * 1024 + 16384) {
        throw const FormatException('서버 응답이 허용 크기를 초과했습니다.');
      }
    }
    final body = builder.takeBytes();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      try {
        code = (jsonDecode(utf8.decode(body)) as Map)['code'] as String?;
      } on FormatException {
        /* Non-JSON proxy errors use the generic message. */
      } on TypeError {
        /* Do not display arbitrary proxy response bodies. */
      }
      if (response.statusCode == 401) {
        if (authenticated && identical(auth.currentSession, session)) {
          await auth.clear();
        }
        throw SyncAuthException(
          code == 'invalid_credentials'
              ? '이메일 또는 비밀번호가 맞지 않습니다.'
              : '다시 로그인해 주세요.',
          code: code,
        );
      }
      if (code == 'invalid_reset_code') {
        throw const SyncAuthException(
          '재설정 코드가 올바르지 않거나 만료되었습니다. 코드를 다시 받아 주세요.',
          code: 'invalid_reset_code',
        );
      }
      if (code == 'mail_unavailable') {
        throw const SyncAuthException(
          '재설정 메일을 보낼 수 없습니다. 서버 관리자의 메일 발송 설정이 필요합니다.',
          code: 'mail_unavailable',
        );
      }
      if (code == 'incorrect_password') {
        throw const SyncAuthException(
          '현재 비밀번호가 맞지 않습니다.',
          code: 'incorrect_password',
        );
      }
      if (response.statusCode == 409) {
        if (code == 'capture_conflict') {
          throw const SyncAuthException(
            '다른 기기에서 이 scrap을 변경했습니다.',
            code: 'capture_conflict',
          );
        }
        throw const FormatException('다른 기기가 먼저 동기화했습니다. 다시 시도해 주세요.');
      }
      if (response.statusCode == 404 && path.startsWith('/v1/capture')) {
        throw const SyncAuthException(
          '서버에 모바일 업로드 기능 업데이트가 필요합니다. 기기에 저장된 내용은 유지됩니다.',
          code: 'capture_unavailable',
        );
      }
      throw SyncAuthException(
        response.statusCode == 429
            ? '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.'
            : '서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.',
        code: code,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
    Duration timeout = const Duration(minutes: 3),
  }) async =>
      jsonDecode(
            utf8.decode(
              await request(
                method,
                path,
                jsonBody: body,
                authenticated: authenticated,
                timeout: timeout,
              ),
            ),
          )
          as Map<String, dynamic>;

  Future<void> dispose() async {
    _http.close();
    await auth.dispose();
  }
}

class SyncAuth {
  SyncAuth(this._client, this._store);
  final SyncClient _client;
  final SyncSessionStore? _store;
  final _changes = StreamController<SyncAuthState>.broadcast();
  SyncSession? currentSession;
  SyncUser? get currentUser => currentSession?.user;
  Stream<SyncAuthState> get onAuthStateChange => _changes.stream;

  Future<void> restore() async {
    final stored = await _store?.read();
    if (stored == null) return;
    try {
      final session = SyncSession.fromJson(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      if (session.expiresAt.isAfter(DateTime.now())) {
        currentSession = session;
        return;
      }
    } on FormatException {
      /* Expired or corrupt sessions require a fresh login. */
    } on TypeError {
      /* Keep the local editor available if session data is invalid. */
    }
    await _store?.delete();
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final json = await _client.json(
      'POST',
      '/v1/auth/login',
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final session = SyncSession.fromJson(json);
    await _store?.write(jsonEncode(json));
    currentSession = session;
    _changes.add(const SyncAuthState(SyncAuthEvent.signedIn));
  }

  Future<void> requestPasswordReset({required String email}) async {
    await _client.json(
      'POST',
      '/v1/auth/password/reset/request',
      body: {'email': email},
      authenticated: false,
    );
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _client.json(
      'POST',
      '/v1/auth/password/reset',
      body: {'email': email, 'code': code, 'new_password': newPassword},
      authenticated: false,
    );
  }

  Future<void> signOut() async {
    try {
      if (currentSession != null) {
        await _client.request('POST', '/v1/auth/logout');
      }
    } finally {
      await clear();
    }
  }

  Future<void> clear() async {
    currentSession = null;
    await _store?.delete();
    _changes.add(const SyncAuthState(SyncAuthEvent.signedOut));
  }

  Future<void> dispose() => _changes.close();
}
