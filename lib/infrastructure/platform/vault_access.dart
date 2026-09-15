import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Owns the platform boundary for choosing and restoring the user's Vault.
///
/// macOS requires a security-scoped bookmark to retain sandbox access across
/// launches. Other desktop platforms can persist and restore the returned path.
class VaultAccess {
  const VaultAccess();

  static const _channel = MethodChannel('scrapnote/vault_access');

  Future<String?> selectDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) return _mobileDirectory();
    if (Platform.isMacOS) {
      return _channel.invokeMethod<String>('selectDirectory');
    }

    return getDirectoryPath(
      confirmButtonText: '이 폴더 사용',
      canCreateDirectories: true,
    );
  }

  Future<String> _mobileDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(path.join(support.path, 'vault'));
    await directory.create(recursive: true);
    return directory.path;
  }

  Future<String?> restoreDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) return _mobileDirectory();
    if (!Platform.isMacOS) {
      return null;
    }
    return _channel.invokeMethod<String>('restoreDirectory');
  }
}
