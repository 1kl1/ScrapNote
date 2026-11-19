import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/location/scrap_metadata_drawer.dart';

class _Tiles extends TileProvider {
  @override
  ImageProvider getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNomLDgPwAF9AKw7aBF7QAAAABJRU5ErkJggg==',
    ),
  );
}

void main() {
  testWidgets(
    'information shows each photo location and hides fallback controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final time = DateTime.utc(2026, 11, 18);
      ScrapAsset photo(String name, double latitude) => ScrapAsset(
        hash: name,
        relativePath: '../$name.jpg',
        originalName: '$name.jpg',
        mimeType: 'image/jpeg',
        location: ScrapLocation(
          latitude: latitude,
          longitude: 127,
          accuracyMeters: 0,
          source: 'photo_exif',
          capturedAt: time,
        ),
      );
      final scrap = Scrap(
        id: 'photos',
        body: '![a](../a.jpg)\n![b](../b.jpg)',
        createdAt: time,
        updatedAt: time,
        assets: [photo('a', 37), photo('b', 38)],
        location: ScrapLocation(
          latitude: 51,
          longitude: 1,
          accuracyMeters: 10,
          source: 'device',
          capturedAt: time,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: ScrapnoteTheme.foruiTheme,
            child: Scaffold(
              body: ScrapMetadataDrawer(scrap: scrap, tileProvider: _Tiles()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('a.jpg'), findsOneWidget);
      expect(find.text('b.jpg'), findsOneWidget);
      expect(find.text('37.000000'), findsOneWidget);
      expect(find.text('38.000000'), findsOneWidget);
      expect(find.text('Photo metadata (EXIF)'), findsNWidgets(2));
      expect(find.text('51.000000'), findsNothing);
      expect(find.byType(FButton), findsNothing);
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
