import 'dart:io';

import 'package:scrapnote/infrastructure/sync/sync_client.dart';

import 'api_sync_remote.dart';
import 'sync_manifest.dart';
import 'vault_sync_engine.dart';

typedef VaultSynchronizer =
    Future<void> Function(
      String vaultPath,
      SyncClient client,
      Map<String, SyncResolution> resolutions,
    );

Future<void> synchronizeVault(
  String vaultPath,
  SyncClient client,
  Map<String, SyncResolution> resolutions,
) => VaultSyncEngine(
  Directory(vaultPath),
  ApiSyncRemote(client),
).synchronize(resolutions: resolutions);
