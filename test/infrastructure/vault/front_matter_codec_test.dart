import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/infrastructure/vault/front_matter_codec.dart';

void main() {
  const codec = ScrapFileCodec();

  test('round-trips all scrap fields and preserves Markdown body', () {
    final scrap = Scrap(
      id: 'scrap:"one"',
      body: '# 기록\n\n---\n\n본문은 : 과 따옴표를 포함한다.',
      createdAt: DateTime.parse('2026-09-04T12:30:00+09:00'),
      updatedAt: DateTime.parse('2026-09-04T12:31:00+09:00'),
      localDate: '2026-09-04',
      utcOffsetMinutes: 540,
      timezoneName: 'Asia/Seoul',
      assets: const [
        ScrapAsset(
          hash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          relativePath: '../assets/sha256/aa/asset.jpg',
          originalName: 'yes: [photo].jpg',
          mimeType: 'image/jpeg',
        ),
      ],
      location: ScrapLocation(
        latitude: 37.5665,
        longitude: 126.978,
        accuracyMeters: 42.5,
        source: 'core_location',
        capturedAt: DateTime.parse('2026-09-04T12:30:02+09:00'),
      ),
    );

    final encoded = codec.encode(scrap);
    final decoded = codec.decode(encoded);

    expect(decoded, scrap);
    expect(encoded, contains('schema: "scrapnote/v1"'));
    expect(encoded, contains('local_date: "2026-09-04"'));
    expect(encoded, contains('utc_offset_minutes: 540'));
    expect(encoded, contains('timezone_name: "Asia/Seoul"'));
    expect(encoded, endsWith(scrap.body));
  });

  test('decodes a file with CRLF delimiters and no optional metadata', () {
    final decoded = codec.decode(
      '---\r\n'
      'schema: scrapnote/v1\r\n'
      'type: scrap\r\n'
      'id: external-1\r\n'
      'created_at: "2026-09-04T00:00:00Z"\r\n'
      'updated_at: "2026-09-04T00:00:00Z"\r\n'
      '---\r\n'
      'External body',
    );

    expect(decoded.id, 'external-1');
    expect(decoded.body, 'External body');
    expect(decoded.assets, isEmpty);
    expect(decoded.location, isNull);
    expect(decoded.localDate, isNull);
    expect(decoded.utcOffsetMinutes, isNull);
    expect(decoded.timezoneName, isNull);

    final legacyLocal = decoded.createdAt.toLocal();
    expect(
      decoded.localCalendarDate,
      DateTime(legacyLocal.year, legacyLocal.month, legacyLocal.day),
    );
  });

  test('rejects unsupported schemas', () {
    const source = '''
---
schema: scrapnote/v2
type: scrap
id: scrap-1
created_at: "2026-09-04T00:00:00Z"
updated_at: "2026-09-04T00:00:00Z"
---
Body
''';

    expect(() => codec.decode(source.trimLeft()), throwsFormatException);
  });

  test('rejects malformed location values', () {
    const source = '''
---
schema: scrapnote/v1
type: scrap
id: scrap-1
created_at: "2026-09-04T00:00:00Z"
updated_at: "2026-09-04T00:00:00Z"
location:
  latitude: 91
  longitude: 127
  accuracy_meters: 10
  source: manual
  captured_at: "2026-09-04T00:00:00Z"
---
Body
''';

    expect(() => codec.decode(source.trimLeft()), throwsFormatException);
  });

  test('rejects an impossible persisted local calendar date', () {
    const source = '''
---
schema: scrapnote/v1
type: scrap
id: scrap-1
created_at: "2026-09-04T00:00:00Z"
updated_at: "2026-09-04T00:00:00Z"
local_date: "2026-02-30"
utc_offset_minutes: 540
timezone_name: "KST"
---
Body
''';

    expect(() => codec.decode(source.trimLeft()), throwsFormatException);
  });
}
