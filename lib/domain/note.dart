import 'scrap.dart';

/// A longer Markdown document stored inside an optional Vault folder.
class Note {
  const Note({
    required this.id,
    required this.body,
    required this.folder,
    required this.createdAt,
    required this.updatedAt,
    required this.filePath,
    this.assets = const <ScrapAsset>[],
  });

  final String id;
  final String body;
  final String folder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String filePath;
  final List<ScrapAsset> assets;

  String get firstLineTitle {
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final value = line.trim();
      if (value.isNotEmpty) {
        return value.replaceFirst(RegExp(r'^#{1,6}\s+'), '').trim();
      }
    }
    return '';
  }

  Note copyWith({
    String? body,
    String? folder,
    DateTime? updatedAt,
    String? filePath,
    List<ScrapAsset>? assets,
  }) {
    return Note(
      id: id,
      body: body ?? this.body,
      folder: folder ?? this.folder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      filePath: filePath ?? this.filePath,
      assets: assets ?? this.assets,
    );
  }
}

class NoteFolder {
  const NoteFolder({required this.id, required this.name});

  /// POSIX-style relative directory below `notes/`; empty means unfiled.
  final String id;
  final String name;
}
