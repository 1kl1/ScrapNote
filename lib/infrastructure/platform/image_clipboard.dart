import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads an image copied to the native macOS pasteboard.
///
/// The native side materializes clipboard bytes as a temporary PNG and
/// returns its path so the regular Vault attachment importer can take over.
abstract final class ImageClipboard {
  static const _channel = MethodChannel('scrapnote/image_clipboard');

  static Future<String?> readImagePath() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return Future<String?>.value();
    }
    return _channel.invokeMethod<String>('readImagePath');
  }
}
