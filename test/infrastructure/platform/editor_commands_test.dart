import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/infrastructure/platform/editor_commands.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('scrapnote/editor_commands');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'routes native save, new-document, and close commands on macOS',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final commands = EditorCommands();
      var saves = 0;
      var newDocuments = 0;
      var closes = 0;
      await commands.start(
        onSaveRequested: () async => saves += 1,
        onNewDocumentRequested: () async => newDocuments += 1,
        onCloseDocumentRequested: () async => closes += 1,
      );

      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('saveRequested')),
        null,
      );
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('newDocumentRequested')),
        null,
      );
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('closeDocumentRequested')),
        null,
      );

      expect(saves, 1);
      expect(newDocuments, 1);
      expect(closes, 1);
      await commands.stop();
    },
  );

  test('does not install a native handler outside macOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final commands = EditorCommands();
    var callbacks = 0;

    await commands.start(
      onSaveRequested: () async => callbacks += 1,
      onNewDocumentRequested: () async => callbacks += 1,
      onCloseDocumentRequested: () async {},
    );
    final response = await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('saveRequested')),
      null,
    );

    expect(response, isNull);
    expect(callbacks, 0);
    await commands.stop();
  });
}
