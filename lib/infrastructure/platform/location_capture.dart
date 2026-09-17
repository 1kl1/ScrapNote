import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/scrap.dart';

typedef ScrapLocationProvider = Future<ScrapLocation?> Function();
typedef LocationPermissionSettingsOpener = Future<bool> Function();

Future<bool> openSystemLocationPermissionSettings() async {
  try {
    return await Geolocator.openAppSettings();
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

/// Captures one foreground position when a new Scrap is first saved.
class LocationCapture {
  const LocationCapture();

  static Future<ScrapLocation?>? _captureInFlight;

  Future<ScrapLocation?> capture() {
    final captureInFlight = _captureInFlight;
    if (captureInFlight != null) {
      return captureInFlight;
    }

    final capture = _captureOnce();
    _captureInFlight = capture;
    return capture.whenComplete(() {
      if (identical(_captureInFlight, capture)) {
        _captureInFlight = null;
      }
    });
  }

  Future<ScrapLocation?> _captureOnce() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return ScrapLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        source: 'device',
        capturedAt: position.timestamp.toUtc(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on PermissionRequestInProgressException {
      return null;
    } on LocationServiceDisabledException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
