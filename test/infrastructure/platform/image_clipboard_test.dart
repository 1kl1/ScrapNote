import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/infrastructure/platform/image_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('scrapnote/image_clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('readImagePath invokes the dedicated macOS channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return '/tmp/scrapnote-paste/copied.png';
    });

    final path = await ImageClipboard.readImagePath();

    expect(receivedCall?.method, 'readImagePath');
    expect(receivedCall?.arguments, isNull);
    expect(path, '/tmp/scrapnote-paste/copied.png');
  });

  test('readImagePath returns null when the pasteboard has no image', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(await ImageClipboard.readImagePath(), isNull);
  });

  test('readImagePath does not use the channel on other platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var invocationCount = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      invocationCount += 1;
      return '/unexpected.png';
    });

    expect(await ImageClipboard.readImagePath(), isNull);
    expect(invocationCount, 0);
  });
}
