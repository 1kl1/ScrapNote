import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/scrap.dart';

typedef ScrapLocationProvider = Future<ScrapLocation?> Function();

/// Captures one foreground position when a new Scrap is first saved.
class LocationCapture {
  const LocationCapture();

  Future<ScrapLocation?> capture() async {
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
    } on LocationServiceDisabledException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
