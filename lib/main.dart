import 'package:flutter/widgets.dart';
import 'package:scrapnote/app/scrapnote_app.dart';
import 'package:scrapnote/infrastructure/sync/sync_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseClient? client;
  try {
    client = await SyncBootstrap.initialize();
  } on Exception {
    // A keychain/session failure must not prevent access to local documents.
  }
  runApp(ScrapnoteApp(syncClient: client));
}
