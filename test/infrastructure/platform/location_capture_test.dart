import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:scrapnote/infrastructure/platform/location_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GeolocatorPlatform originalPlatform;

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalPlatform;
  });

  test('concurrent captures share one permission request', () async {
    final permission = Completer<LocationPermission>();
    final platform = _FakeGeolocatorPlatform(permission: permission);
    GeolocatorPlatform.instance = platform;

    final firstCapture = const LocationCapture().capture();
    final secondCapture = const LocationCapture().capture();

    await Future<void>.delayed(Duration.zero);
    expect(platform.permissionRequestCount, 1);
    permission.complete(LocationPermission.whileInUse);

    final locations = await Future.wait([firstCapture, secondCapture]);
    expect(platform.permissionRequestCount, 1);
    expect(platform.positionRequestCount, 1);
    expect(locations[0]?.latitude, 37.5665);
    expect(locations[1], locations[0]);
  });

  test(
    'permission request already in progress does not fail capture',
    () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        permissionError: const PermissionRequestInProgressException(null),
      );

      expect(await const LocationCapture().capture(), isNull);
    },
  );

  test('opens app settings for a permanently denied permission', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;

    expect(await openSystemLocationPermissionSettings(), isTrue);
    expect(platform.appSettingsOpenCount, 1);
  });
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({this.permission, this.permissionError});

  final Completer<LocationPermission>? permission;
  final Exception? permissionError;
  int permissionRequestCount = 0;
  int positionRequestCount = 0;
  int appSettingsOpenCount = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() {
    permissionRequestCount += 1;
    final error = permissionError;
    if (error != null) {
      return Future<LocationPermission>.error(error);
    }
    return permission?.future ?? Future.value(LocationPermission.whileInUse);
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    positionRequestCount += 1;
    return Future.value(
      Position(
        latitude: 37.5665,
        longitude: 126.978,
        timestamp: DateTime.utc(2026, 9, 15),
        accuracy: 8,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpenCount += 1;
    return true;
  }
}
