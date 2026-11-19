import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

/// Keep the old mobile Supabase Vault intact while restoring the new server.
/// The desktop Vault is rebound only by the verified local migration tool.
Future<Directory> resolveMobileVaultDirectory(Directory support) async {
  final legacy = Directory(path.join(support.path, 'vault'));
  final state = File(path.join(legacy.path, '.sync', 'state.json'));
  var directory = legacy;
  if (await state.exists()) {
    try {
      final decoded = jsonDecode(await state.readAsString());
      final identity = decoded is Map ? decoded['identity'] : null;
      final host = identity is String ? Uri.tryParse(identity)?.host : null;
      if (host != null && host.endsWith('.supabase.co')) {
        directory = Directory(path.join(support.path, 'vault-oracle'));
      }
    } on FormatException {
      // A damaged old state must never make existing local documents disappear.
    }
  }
  await directory.create(recursive: true);
  return directory;
}
