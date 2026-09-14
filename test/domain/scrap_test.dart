import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/domain/scrap.dart';

void main() {
  group('Scrap.firstLineTitle', () {
    test('returns the first non-empty trimmed line', () {
      final scrap = Scrap(
        id: 'scrap-1',
        body: '\n  A small observation  \nMore detail',
        createdAt: DateTime.utc(2026, 9, 4),
        updatedAt: DateTime.utc(2026, 9, 4),
      );

      expect(scrap.firstLineTitle, 'A small observation');
    });

    test('removes an ATX heading marker', () {
      final scrap = Scrap(
        id: 'scrap-1',
        body: '### A heading\nBody',
        createdAt: DateTime.utc(2026, 9, 4),
        updatedAt: DateTime.utc(2026, 9, 4),
      );

      expect(scrap.firstLineTitle, 'A heading');
    });

    test('returns an empty string for an empty body', () {
      final scrap = Scrap(
        id: 'scrap-1',
        body: ' \n\t',
        createdAt: DateTime.utc(2026, 9, 4),
        updatedAt: DateTime.utc(2026, 9, 4),
      );

      expect(scrap.firstLineTitle, isEmpty);
    });
  });

  test('value equality includes assets and location', () {
    final capturedAt = DateTime.utc(2026, 9, 4, 3);
    final left = Scrap(
      id: 'scrap-1',
      body: 'Body',
      createdAt: capturedAt,
      updatedAt: capturedAt,
      assets: const [
        ScrapAsset(
          hash: 'abc',
          relativePath: '../assets/abc.jpg',
          originalName: 'photo.jpg',
          mimeType: 'image/jpeg',
        ),
      ],
      location: ScrapLocation(
        latitude: 37.5,
        longitude: 127,
        accuracyMeters: 20,
        source: 'manual',
        capturedAt: capturedAt,
      ),
    );
    final right = Scrap(
      id: 'scrap-1',
      body: 'Body',
      createdAt: capturedAt,
      updatedAt: capturedAt,
      assets: const [
        ScrapAsset(
          hash: 'abc',
          relativePath: '../assets/abc.jpg',
          originalName: 'photo.jpg',
          mimeType: 'image/jpeg',
        ),
      ],
      location: ScrapLocation(
        latitude: 37.5,
        longitude: 127,
        accuracyMeters: 20,
        source: 'manual',
        capturedAt: capturedAt,
      ),
    );

    expect(left, right);
    expect(left.hashCode, right.hashCode);
  });

  group('Scrap.localCalendarDate', () {
    test('uses the calendar date persisted at capture time', () {
      final scrap = Scrap(
        id: 'scrap-date',
        body: 'Late-night note',
        createdAt: DateTime.utc(2026, 9, 3, 15, 30),
        updatedAt: DateTime.utc(2026, 9, 3, 15, 30),
        localDate: '2026-09-04',
        utcOffsetMinutes: 540,
        timezoneName: 'KST',
      );

      expect(scrap.localCalendarDate, DateTime(2026, 9, 4));
    });

    test('uses the stored offset when only the calendar date is absent', () {
      final scrap = Scrap(
        id: 'scrap-offset',
        body: 'Late-night note',
        createdAt: DateTime.utc(2026, 9, 3, 23, 30),
        updatedAt: DateTime.utc(2026, 9, 3, 23, 30),
        utcOffsetMinutes: 120,
      );

      expect(scrap.localCalendarDate, DateTime(2026, 9, 4));
    });

    test('legacy scraps fall back to createdAt in the current time zone', () {
      final createdAt = DateTime.utc(2026, 9, 3, 23, 30);
      final local = createdAt.toLocal();
      final scrap = Scrap(
        id: 'legacy',
        body: 'Legacy',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      expect(
        scrap.localCalendarDate,
        DateTime(local.year, local.month, local.day),
      );
    });
  });
}
