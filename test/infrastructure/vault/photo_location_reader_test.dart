import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/infrastructure/vault/photo_location_reader.dart';

import '../../support/photo_fixture.dart';

void main() {
  late Directory sandbox;
  final fallback = DateTime.utc(2026, 11, 18);
  const reader = PhotoLocationReader();

  setUp(
    () async => sandbox = await Directory.systemTemp.createTemp('photo-gps-'),
  );
  tearDown(() => sandbox.delete(recursive: true));

  test(
    'reads actual JPEG DMS coordinates, hemispheres, and UTC GPS time',
    () async {
      final file = await writePhoto(
        File('${sandbox.path}/photo.jpg'),
        southWest: true,
      );
      final result = await reader.read(file, fallbackTime: fallback);
      expect(result?.latitude, -37.5);
      expect(result?.longitude, -127.25);
      expect(result?.source, 'photo_exif');
      expect(result?.capturedAt, DateTime.utc(2026, 9, 4, 9, 2, 3));
    },
  );

  test(
    'missing, corrupt, or absent metadata produces no photo location',
    () async {
      final plain = await writePhoto(
        File('${sandbox.path}/plain.jpg'),
        gps: false,
      );
      final broken = await File(
        '${sandbox.path}/broken.heic',
      ).writeAsBytes([0, 1, 2]);
      for (final file in [plain, broken, File('${sandbox.path}/missing.jpg')]) {
        expect(await reader.read(file, fallbackTime: fallback), isNull);
      }
    },
  );

  test(
    'rejects incomplete GPS, out of range values, and zero denominators',
    () async {
      final file = await writePhoto(File('${sandbox.path}/photo.jpg'));
      final tags = await readExifFromFile(file);
      final missingRef = {...tags}..remove('GPS GPSLatitudeRef');
      expect(
        PhotoLocationReader.fromTags(missingRef, fallbackTime: fallback),
        isNull,
      );
      for (final values in [
        [Ratio(91, 1), Ratio(0, 1), Ratio(0, 1)],
        [Ratio(37, 1), Ratio(60, 1), Ratio(0, 1)],
        [Ratio(37, 0), Ratio(0, 1), Ratio(0, 1)],
      ]) {
        final invalid = {
          ...tags,
          'GPS GPSLatitude': IfdTag(
            tag: 2,
            tagType: 'Ratio',
            printable: '',
            values: IfdRatios(values),
          ),
        };
        expect(
          PhotoLocationReader.fromTags(invalid, fallbackTime: fallback),
          isNull,
        );
      }
    },
  );

  test(
    'GPS without a usable timestamp retains its position and fallback time',
    () async {
      final file = await writePhoto(File('${sandbox.path}/photo.jpg'));
      final tags = await readExifFromFile(file);
      tags.remove('GPS GPSDate');
      final location = PhotoLocationReader.fromTags(
        tags,
        fallbackTime: fallback,
      );
      expect(location?.latitude, 37.5);
      expect(location?.capturedAt, fallback);
    },
  );
}
