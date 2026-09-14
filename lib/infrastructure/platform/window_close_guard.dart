import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef WindowCloseRequest = Future<bool> Function();

/// Bridges macOS's synchronous window close request to an async Dart prompt.
///
/// Call [start] once the editor session is ready. Returning `true` from the
/// handler lets the pending native close continue; `false` keeps the window
/// open. Call [stop] before replacing or disposing the guard.
class WindowCloseGuard {
  WindowCloseGuard();

  static const _channel = MethodChannel('scrapnote/window_close_guard');

  WindowCloseRequest? _onCloseRequested;

  Future<void> start(WindowCloseRequest onCloseRequested) async {
    _onCloseRequested = onCloseRequested;
    if (!_isMacOS) {
      return;
    }
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      await _channel.invokeMethod<void>('setEnabled', true);
    } catch (_) {
      _channel.setMethodCallHandler(null);
      _onCloseRequested = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    _onCloseRequested = null;
    if (!_isMacOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setEnabled', false);
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'closeRequested') {
      throw MissingPluginException(
        'Unknown window close method ${call.method}.',
      );
    }
    final handler = _onCloseRequested;
    return handler == null ? true : handler();
  }

  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
}
