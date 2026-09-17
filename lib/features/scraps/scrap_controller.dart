import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/infrastructure/platform/vault_access.dart';
import 'package:scrapnote/infrastructure/platform/location_capture.dart';
import 'package:scrapnote/infrastructure/vault/vault_repository.dart';

typedef DirectoryPicker = Future<String?> Function();
typedef DirectoryRestorer = Future<String?> Function();
typedef SupportDirectoryProvider = Future<Directory> Function();
typedef VaultRepositoryFactory = VaultRepository Function(Directory root);

/// Coordinates the first local-first vertical slice: connect a vault, load its
/// Markdown scraps, and persist new ones without making the UI own file I/O.
class ScrapController extends ChangeNotifier {
  ScrapController({
    DirectoryPicker? directoryPicker,
    DirectoryRestorer? directoryRestorer,
    SupportDirectoryProvider? supportDirectoryProvider,
    VaultRepositoryFactory? repositoryFactory,
    ScrapLocationProvider? locationProvider,
    LocationPermissionSettingsOpener? locationSettingsOpener,
  }) : _directoryPicker =
           directoryPicker ?? const VaultAccess().selectDirectory,
       _directoryRestorer =
           directoryRestorer ?? const VaultAccess().restoreDirectory,
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _repositoryFactory = repositoryFactory ?? VaultRepository.new,
       _locationProvider = locationProvider ?? const LocationCapture().capture,
       _locationSettingsOpener =
           locationSettingsOpener ?? openSystemLocationPermissionSettings;

  static const _settingsFileName = 'settings.json';

  final DirectoryPicker _directoryPicker;
  final DirectoryRestorer _directoryRestorer;
  final SupportDirectoryProvider _supportDirectoryProvider;
  final VaultRepositoryFactory _repositoryFactory;
  final ScrapLocationProvider _locationProvider;
  final LocationPermissionSettingsOpener _locationSettingsOpener;

  VaultRepository? _repository;
  List<Scrap> _scraps = const [];
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  List<Scrap> get scraps => List.unmodifiable(_scraps);
  bool get loading => _loading;
  bool get saving => _saving;
  String? get errorMessage => _errorMessage;
  String? get vaultPath => _repository?.root.path;
  bool get hasVault => _repository != null;

  Future<void> initialize() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final settings = await _readSettings();
      final restoredPath = await _directoryRestorer();
      final savedPath = restoredPath ?? settings['vaultPath'];
      if (savedPath is String && savedPath.isNotEmpty) {
        final directory = Directory(savedPath);
        if (await directory.exists()) {
          await _connect(directory, persist: false);
        }
      }
    } on FileSystemException {
      _errorMessage = '저장소에 다시 접근할 수 없습니다. Vault 폴더를 다시 선택해 주세요.';
    } on FormatException {
      _errorMessage = '저장소 설정을 읽지 못했습니다. Vault를 다시 선택해 주세요.';
    } on PlatformException {
      _errorMessage = '저장된 Vault 권한을 복원하지 못했습니다. 폴더를 다시 선택해 주세요.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> chooseVault() async {
    try {
      final selectedPath = await _directoryPicker();
      if (selectedPath == null) {
        return false;
      }

      _loading = true;
      _errorMessage = null;
      notifyListeners();
      await _connect(Directory(selectedPath), persist: true);
      return true;
    } on FileSystemException catch (error) {
      _errorMessage =
          '선택한 폴더를 사용할 수 없습니다. 읽기·쓰기 권한을 확인해 주세요. '
          '(${error.osError?.message ?? error.message})';
      return false;
    } on PlatformException catch (error) {
      _errorMessage = error.message ?? 'Vault 접근 권한을 저장하지 못했습니다.';
      return false;
    } on FormatException catch (error) {
      _errorMessage = 'Vault의 Scrap 파일을 읽지 못했습니다. ${error.message}';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> saveScrap(
    String body, {
    Iterable<String> attachmentPaths = const <String>[],
  }) async {
    return await saveDocument(body, attachmentPaths: attachmentPaths) != null;
  }

  /// Saves a new document or updates [existing], returning the persisted value.
  ///
  /// Returning `null` means validation, Vault selection, or persistence failed;
  /// [errorMessage] contains user-facing detail when applicable.
  Future<Scrap?> saveDocument(
    String body, {
    Scrap? existing,
    Iterable<String> attachmentPaths = const <String>[],
  }) async {
    if (_saving) {
      return null;
    }

    final attachments = attachmentPaths
        .map((attachment) => attachment.trim())
        .where((attachment) => attachment.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (body.trim().isEmpty && attachments.isEmpty) {
      _errorMessage = '빈 Scrap은 저장하지 않았습니다. 글이나 이미지를 먼저 추가해 주세요.';
      notifyListeners();
      return null;
    }

    if (_repository == null && !await chooseVault()) {
      return null;
    }

    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final scrap = existing == null
          ? await _repository!.createScrap(
              body,
              attachmentPaths: attachments,
              location: await _locationProvider(),
            )
          : await _repository!.updateScrap(
              existing,
              body,
              attachmentPaths: attachments,
            );
      _scraps = existing == null
          ? [scrap, ..._scraps]
          : _replaceAndSort(_scraps, scrap);
      return scrap;
    } on FileSystemException catch (error) {
      _errorMessage =
          'Scrap을 저장하지 못했습니다. 편집 내용은 그대로 유지됩니다. '
          '(${error.osError?.message ?? error.message})';
      return null;
    } on FormatException catch (error) {
      _errorMessage = 'Scrap 파일 형식이 올바르지 않습니다. ${error.message}';
      return null;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> deleteScrap(String id) async {
    if (_repository == null || _saving) return false;
    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository!.deleteScrap(id);
      _scraps = _scraps.where((scrap) => scrap.id != id).toList();
      return true;
    } on FileSystemException catch (error) {
      _errorMessage = 'Scrap을 삭제하지 못했습니다. ${error.message}';
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Tries device location again for an already-saved Scrap.
  Future<Scrap?> captureLocationForScrap(Scrap scrap) async {
    if (_repository == null || _saving) return null;
    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final location = await _locationProvider();
      if (location == null) {
        _errorMessage =
            '위치를 저장하지 못했습니다. 위치 정보에서 앱 설정을 열어 권한을 허용하거나 수동으로 지정해 주세요.';
        return null;
      }
      return await _persistLocation(scrap, location);
    } on FileSystemException catch (error) {
      _errorMessage = '위치를 Scrap에 저장하지 못했습니다. ${error.message}';
      return null;
    } on FormatException catch (error) {
      _errorMessage = error.message;
      return null;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Persists a manually selected location for an already-saved Scrap.
  Future<Scrap?> setLocationForScrap(
    Scrap scrap,
    ScrapLocation location,
  ) async {
    if (_repository == null || _saving) return null;
    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _persistLocation(scrap, location);
    } on FileSystemException catch (error) {
      _errorMessage = '위치를 Scrap에 저장하지 못했습니다. ${error.message}';
      return null;
    } on FormatException catch (error) {
      _errorMessage = error.message;
      return null;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Opens this app's system settings so a permanently denied permission can
  /// be changed without leaving the recovery flow unexplained.
  Future<bool> openLocationPermissionSettings() async {
    _errorMessage = null;
    notifyListeners();
    try {
      final opened = await _locationSettingsOpener();
      if (!opened) {
        _errorMessage = '앱 설정을 열지 못했습니다. 시스템 설정에서 Scrapnote의 위치 권한을 허용해 주세요.';
      }
      return opened;
    } on PlatformException {
      _errorMessage = '앱 설정을 열지 못했습니다. 시스템 설정에서 Scrapnote의 위치 권한을 허용해 주세요.';
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<Scrap> _persistLocation(Scrap scrap, ScrapLocation location) async {
    final updated = await _repository!.updateScrapLocation(scrap, location);
    _scraps = _replaceAndSort(_scraps, updated);
    return updated;
  }

  static List<Scrap> _replaceAndSort(List<Scrap> scraps, Scrap replacement) {
    final result =
        <Scrap>[
          replacement,
          ...scraps.where((scrap) => scrap.id != replacement.id),
        ]..sort((left, right) {
          final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
          return byUpdatedAt != 0
              ? byUpdatedAt
              : right.createdAt.compareTo(left.createdAt);
        });
    return result;
  }

  Future<void> reload() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _scraps = await repository.listScraps();
    } on FileSystemException catch (error) {
      _errorMessage =
          'Vault를 다시 읽지 못했습니다. '
          '(${error.osError?.message ?? error.message})';
    } on FormatException catch (error) {
      _errorMessage = 'Vault의 Scrap 파일을 읽지 못했습니다. ${error.message}';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _connect(Directory directory, {required bool persist}) async {
    final repository = _repositoryFactory(directory);
    await repository.initialize();
    final scraps = await repository.listScraps();
    _repository = repository;
    _scraps = scraps;
    if (persist) {
      await _writeSettings({'vaultPath': directory.path});
    }
  }

  Future<Map<String, Object?>> _readSettings() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return const {};
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('settings.json must contain an object.');
    }
    return value;
  }

  Future<void> _writeSettings(Map<String, Object?> value) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  Future<File> _settingsFile() async {
    final supportDirectory = await _supportDirectoryProvider();
    return File(path.join(supportDirectory.path, _settingsFileName));
  }
}
