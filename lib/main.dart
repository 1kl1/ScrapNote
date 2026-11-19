import 'package:flutter/widgets.dart';
import 'package:scrapnote/app/scrapnote_app.dart';
import 'package:scrapnote/infrastructure/sync/sync_bootstrap.dart';
import 'package:scrapnote/infrastructure/sync/sync_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SyncClient? client;
  try {
    client = await SyncBootstrap.initialize();
  } on Exception {}
  runApp(ScrapnoteApp(syncClient: client));
}
