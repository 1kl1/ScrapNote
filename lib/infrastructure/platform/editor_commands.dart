import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef EditorCommandCallback = Future<void> Function();

/// Receives desktop commands that AppKit consumes before Flutter key handling.
class EditorCommands {
  static const _channel = MethodChannel('scrapnote/editor_commands');

  EditorCommandCallback? _onSaveRequested;
  EditorCommandCallback? _onNewDocumentRequested;
  EditorCommandCallback? _onCloseDocumentRequested;

  Future<void> start({
    required EditorCommandCallback onSaveRequested,
    required EditorCommandCallback onNewDocumentRequested,
    required EditorCommandCallback onCloseDocumentRequested,
  }) async {
    _onSaveRequested = onSaveRequested;
    _onNewDocumentRequested = onNewDocumentRequested;
    _onCloseDocumentRequested = onCloseDocumentRequested;
    if (!_isMacOS) {
      return;
    }
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> stop() async {
    _onSaveRequested = null;
    _onNewDocumentRequested = null;
    _onCloseDocumentRequested = null;
    if (_isMacOS) {
      _channel.setMethodCallHandler(null);
    }
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'saveRequested':
        await _onSaveRequested?.call();
      case 'newDocumentRequested':
        await _onNewDocumentRequested?.call();
      case 'closeDocumentRequested':
        await _onCloseDocumentRequested?.call();
      default:
        throw MissingPluginException('Unknown editor command ${call.method}.');
    }
    return null;
  }

  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
}
