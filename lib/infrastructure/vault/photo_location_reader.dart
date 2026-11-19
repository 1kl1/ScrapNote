import 'dart:io';
import 'dart:isolate';

import 'package:exif/exif.dart';

import '../../domain/scrap.dart';

/// Read the original before resizing: optimized files may have no EXIF left.
class PhotoLocationReader {
  const PhotoLocationReader();

  Future<ScrapLocation?> read(
    File file, {
    required DateTime fallbackTime,
  }) => Isolate.run(() async {
    try {
      final tags = await readExifFromFile(file, details: false);
      return fromTags(tags, fallbackTime: fallbackTime);
    } catch (_) {
      // Missing, unsupported, or malformed metadata must not prevent saving.
      return null;
    }
  });

  static ScrapLocation? fromTags(
    Map<String, IfdTag> tags, {
    required DateTime fallbackTime,
  }) {
    final latitude = _coordinate(tags, 'Latitude', 'N', 'S', 90);
    final longitude = _coordinate(tags, 'Longitude', 'E', 'W', 180);
    if (latitude == null || longitude == null) return null;
    final accuracyValues = _numbers(tags['GPS GPSHPositioningError']);
    final accuracy =
        accuracyValues.length == 1 &&
            accuracyValues.single.isFinite &&
            accuracyValues.single >= 0
        ? accuracyValues.single
        : 0.0;
    return ScrapLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
      source: 'photo_exif',
      capturedAt: _gpsTime(tags) ?? _originalTime(tags) ?? fallbackTime.toUtc(),
    );
  }

  static double? _coordinate(
    Map<String, IfdTag> tags,
    String name,
    String positive,
    String negative,
    double limit,
  ) {
    final ref = tags['GPS GPS${name}Ref']?.printable.trim().toUpperCase();
    if (ref != positive && ref != negative) return null;
    final values = _numbers(tags['GPS GPS$name']);
    if (values.length != 3 ||
        values.any((v) => !v.isFinite || v < 0) ||
        values[1] >= 60 ||
        values[2] >= 60) {
      return null;
    }
    final degrees = values[0] + values[1] / 60 + values[2] / 3600;
    if (degrees > limit) return null;
    return ref == negative ? -degrees : degrees;
  }

  static List<double> _numbers(IfdTag? tag) => [
    for (final value in tag?.values.toList() ?? [])
      if (value is Ratio)
        value.toDouble()
      else if (value is num)
        value.toDouble(),
  ];

  static DateTime? _gpsTime(Map<String, IfdTag> tags) {
    final date = tags['GPS GPSDate']?.printable;
    final time = _numbers(tags['GPS GPSTimeStamp']);
    if (date == null ||
        time.length != 3 ||
        time.any((v) => !v.isFinite || v < 0) ||
        time[0] >= 24 ||
        time[1] >= 60 ||
        time[2] >= 60) {
      return null;
    }
    final day = DateTime.tryParse('${date.replaceAll(':', '-')}T00:00:00Z');
    return day?.add(
      Duration(
        microseconds: ((time[0] * 3600 + time[1] * 60 + time[2]) * 1000000)
            .round(),
      ),
    );
  }

  static DateTime? _originalTime(Map<String, IfdTag> tags) {
    final value = tags['EXIF DateTimeOriginal']?.printable;
    final offset = tags['EXIF OffsetTimeOriginal']?.printable;
    // An unzoned wall clock cannot reliably order photos from different zones.
    if (value == null ||
        offset == null ||
        !RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(offset)) {
      return null;
    }
    final match = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}:\d{2}:\d{2})$',
    ).firstMatch(value);
    if (match == null) return null;
    return DateTime.tryParse(
      '${match[1]}-${match[2]}-${match[3]}T${match[4]}$offset',
    )?.toUtc();
  }
}
