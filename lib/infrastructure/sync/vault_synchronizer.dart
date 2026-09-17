import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_sync_remote.dart';
import 'sync_bootstrap.dart';
import 'sync_manifest.dart';
import 'vault_sync_engine.dart';

typedef VaultSynchronizer =
    Future<void> Function(
      String vaultPath,
      SupabaseClient client,
      Map<String, SyncResolution> resolutions,
    );

Future<void> synchronizeVault(
  String vaultPath,
  SupabaseClient client,
  Map<String, SyncResolution> resolutions,
) => VaultSyncEngine(
  Directory(vaultPath),
  SupabaseSyncRemote(client, SyncBootstrap.url),
).synchronize(resolutions: resolutions);
