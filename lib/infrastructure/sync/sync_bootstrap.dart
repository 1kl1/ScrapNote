import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Public client configuration; authorization is enforced by server-side RLS.
abstract final class SyncBootstrap {
  static const authRedirectUrl = 'com.scrapnote.app://auth-callback';

  static bool isAuthCallback(Uri uri) =>
      uri.scheme == 'com.scrapnote.app' &&
      uri.host == 'auth-callback' &&
      (uri.path.isEmpty || uri.path == '/') &&
      uri.userInfo.isEmpty &&
      !uri.hasPort;
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bgprybazlurcalbdinml.supabase.co',
  );
  static const key = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_mdHopOec03V_d1mJuIntUA_XTBANoad',
  );

  static Future<SupabaseClient> initialize() async {
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SecureSessionStorage(),
        detectSessionInUriPredicate: isAuthCallback,
      ),
    );
    return Supabase.instance.client;
  }
}

class _SecureSessionStorage extends LocalStorage {
  const _SecureSessionStorage();
  // The login keychain also supports the existing ad-hoc signed macOS build.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  String get _key => 'scrapnote-session-${Uri.parse(SyncBootstrap.url).host}';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
