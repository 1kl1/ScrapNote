import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

/// Owns the platform boundary for choosing and restoring the user's Vault.
///
/// macOS requires a security-scoped bookmark to retain sandbox access across
/// launches. Other desktop platforms can persist and restore the returned path.
class VaultAccess {
  const VaultAccess();

  static const _channel = MethodChannel('scrapnote/vault_access');

  Future<String?> selectDirectory() async {
    if (Platform.isMacOS) {
      return _channel.invokeMethod<String>('selectDirectory');
    }

    return getDirectoryPath(
      confirmButtonText: '이 폴더 사용',
      canCreateDirectories: true,
    );
  }

  Future<String?> restoreDirectory() async {
    if (!Platform.isMacOS) {
      return null;
    }
    return _channel.invokeMethod<String>('restoreDirectory');
  }
}
