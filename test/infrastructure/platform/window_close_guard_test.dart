import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/infrastructure/platform/window_close_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('scrapnote/window_close_guard');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('enables the native guard and answers close requests', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final outgoing = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      outgoing.add(call);
      return null;
    });
    final guard = WindowCloseGuard();
    var requestCount = 0;

    await guard.start(() async {
      requestCount += 1;
      return false;
    });
    final response = await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('closeRequested')),
      null,
    );

    expect(outgoing, hasLength(1));
    expect(outgoing.single.method, 'setEnabled');
    expect(outgoing.single.arguments, isTrue);
    expect(requestCount, 1);
    expect(codec.decodeEnvelope(response!), isFalse);

    await guard.stop();
    expect(outgoing.last.method, 'setEnabled');
    expect(outgoing.last.arguments, isFalse);
  });

  test('returns true when the user approves the pending close', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final guard = WindowCloseGuard();
    await guard.start(() async => true);

    final response = await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('closeRequested')),
      null,
    );

    expect(codec.decodeEnvelope(response!), isTrue);
    await guard.stop();
  });

  test('does not touch the platform channel outside macOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls += 1;
      return null;
    });
    final guard = WindowCloseGuard();

    await guard.start(() async => true);
    await guard.stop();

    expect(calls, 0);
  });
}
