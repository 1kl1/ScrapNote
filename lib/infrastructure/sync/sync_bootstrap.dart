import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'sync_client.dart';

abstract final class SyncBootstrap {
  static const url = String.fromEnvironment(
    'SCRAPNOTE_API_URL',
    defaultValue: 'https://scrapnote.134.185.114.149.sslip.io',
  );

  static Future<SyncClient> initialize() async {
    final client = SyncClient(url, sessionStore: _SecureSessionStorage(url));
    await client.auth.restore();
    return client;
  }
}

class _SecureSessionStorage implements SyncSessionStore {
  const _SecureSessionStorage(this.url);
  final String url;
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  String get _key => 'scrapnote-api-session-${Uri.parse(url).origin}';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}
