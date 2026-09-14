import 'dart:io';

import '../../features/editor/inline_image.dart';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../domain/note.dart';
import '../../domain/scrap.dart';
import 'note_file_codec.dart';

typedef NoteIdGenerator = String Function();
typedef NoteClock = DateTime Function();

class NoteRepository {
  NoteRepository(
    this.root, {
    NoteFileCodec? codec,
    NoteIdGenerator? idGenerator,
    NoteClock? now,
  }) : codec = codec ?? const NoteFileCodec(),
       _idGenerator = idGenerator ?? const Uuid().v7,
       _now = now ?? DateTime.now;

  final Directory root;
  final NoteFileCodec codec;
  final NoteIdGenerator _idGenerator;
  final NoteClock _now;

  Directory get notesDirectory => Directory(path.join(root.path, 'notes'));
  Directory get assetsDirectory =>
      Directory(path.join(root.path, 'assets', 'sha256'));

  Future<void> initialize() async {
    await notesDirectory.create(recursive: true);
    await assetsDirectory.create(recursive: true);
  }

  Future<List<NoteFolder>> listFolders() async {
    await initialize();
    final folders = <NoteFolder>[const NoteFolder(id: '', name: 'Unfiled')];
    await for (final entity in notesDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Directory) {
        final name = path.basename(entity.path);
        folders.add(
          NoteFolder(
            id: path.relative(entity.path, from: notesDirectory.path),
            name: name,
          ),
        );
      }
    }
    folders.sort((left, right) {
      if (left.id.isEmpty) return -1;
      if (right.id.isEmpty) return 1;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return List<NoteFolder>.unmodifiable(folders);
  }

  Future<NoteFolder> createFolder(
    String requestedName, {
    String parent = '',
  }) async {
    await initialize();
    final name = requestedName.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[/\\:]'))) {
      throw const FormatException(
        'Folder names cannot be empty or contain /, \\, or :.',
      );
    }
    final directory = Directory(path.join(_folderDirectory(parent).path, name));
    await directory.create(recursive: false);
    return NoteFolder(
      id: path.relative(directory.path, from: notesDirectory.path),
      name: name,
    );
  }

  Future<List<Note>> listNotes() async {
    await initialize();
    final notes = <Note>[];
    await for (final entity in notesDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          path.extension(entity.path).toLowerCase() == '.md') {
        notes.add(
          codec.decode(await entity.readAsString(), filePath: entity.path),
        );
      }
    }
    notes.sort(_compareModified);
    return List<Note>.unmodifiable(notes);
  }

  Future<Note> createNote(
    String body, {
    required String folder,
    Iterable<String> attachmentPaths = const <String>[],
  }) async {
    await initialize();
    final directory = _folderDirectory(folder);
    await directory.create(recursive: true);
    final assets = await _importAssets(
      attachmentPaths,
      relativeFrom: directory,
    );
    final now = _now().toUtc();
    final id = _idGenerator();
    final file = File(
      path.join(directory.path, '${_stamp(now)}--${_safe(id)}.md'),
    );
    final note = Note(
      id: id,
      body: await _resolveAssetLinks(body, attachmentPaths, directory),
      folder: folder,
      createdAt: now,
      updatedAt: now,
      filePath: file.path,
      assets: assets,
    );
    await _atomicWrite(file, codec.encode(note));
    return note;
  }

  Future<Note> updateNote(
    Note existing,
    String body, {
    Iterable<String> attachmentPaths = const <String>[],
  }) async {
    final file = File(existing.filePath);
    if (!await file.exists()) {
      throw FileSystemException(
        'The Note no longer exists.',
        existing.filePath,
      );
    }
    final persisted = codec.decode(
      await file.readAsString(),
      filePath: file.path,
    );
    final added = await _importAssets(
      attachmentPaths,
      relativeFrom: file.parent,
    );
    final hashes = persisted.assets.map((asset) => asset.hash).toSet();
    final uniqueAdded = added
        .where((asset) => hashes.add(asset.hash))
        .toList(growable: false);
    final note = Note(
      id: persisted.id,
      body: await _resolveAssetLinks(body, attachmentPaths, file.parent),
      folder: persisted.folder,
      createdAt: persisted.createdAt,
      updatedAt: _now().toUtc(),
      filePath: file.path,
      assets: List<ScrapAsset>.unmodifiable(<ScrapAsset>[
        ...persisted.assets,
        ...uniqueAdded,
      ]),
    );
    await _atomicWrite(file, codec.encode(note));
    return note;
  }

  Directory _folderDirectory(String folder) {
    final target = path.normalize(path.join(notesDirectory.path, folder));
    if (target != notesDirectory.path &&
        !path.isWithin(notesDirectory.path, target)) {
      throw const FormatException('Folder must be inside Notes.');
    }
    return Directory(target);
  }

  Future<String> _resolveAssetLinks(
    String body,
    Iterable<String> sources,
    Directory directory,
  ) async {
    for (final source in sources.toSet()) {
      final assets = await _importAssets([source], relativeFrom: directory);
      final asset = assets.single;
      body = InlineImage.persist(
        body,
        source,
        asset.relativePath,
        asset.originalName,
      );
    }
    return body;
  }

  Future<List<ScrapAsset>> _importAssets(
    Iterable<String> paths, {
    required Directory relativeFrom,
  }) async {
    final assets = <ScrapAsset>[];
    final seen = <String>{};
    for (final sourcePath in paths) {
      final source = File(sourcePath);
      if (!await source.exists()) {
        throw FileSystemException('Attachment does not exist.', sourcePath);
      }
      final hash = (await sha256.bind(source.openRead()).first).toString();
      if (!seen.add(hash)) continue;
      final bucket = Directory(
        path.join(assetsDirectory.path, hash.substring(0, 2)),
      );
      await bucket.create(recursive: true);
      final extension = path.extension(sourcePath).toLowerCase();
      final stored = File(path.join(bucket.path, '$hash$extension'));
      if (!await stored.exists()) {
        await source.copy(stored.path);
      }
      assets.add(
        ScrapAsset(
          hash: hash,
          relativePath: path
              .relative(stored.path, from: relativeFrom.path)
              .replaceAll(r'\', '/'),
          originalName: path.basename(sourcePath),
          mimeType: _mimeType(extension),
        ),
      );
    }
    return List<ScrapAsset>.unmodifiable(assets);
  }

  static Future<void> _atomicWrite(File file, String contents) async {
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static String _stamp(DateTime value) =>
      value.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  static int _compareModified(Note left, Note right) {
    final value = right.updatedAt.compareTo(left.updatedAt);
    return value != 0 ? value : right.id.compareTo(left.id);
  }

  static String _mimeType(String extension) => switch (extension) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.heic' => 'image/heic',
    '.heif' => 'image/heif',
    '.tif' || '.tiff' => 'image/tiff',
    '.bmp' => 'image/bmp',
    _ => 'application/octet-stream',
  };
}
