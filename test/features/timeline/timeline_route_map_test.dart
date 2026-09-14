import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/timeline/timeline_route_map.dart';

Scrap scrap(String id, int hour, double lat, {bool located = true}) => Scrap(
  id: id,
  body: id,
  createdAt: DateTime.utc(2026, 9, 12, hour),
  updatedAt: DateTime.utc(2026, 9, 15),
  location: !located
      ? null
      : ScrapLocation(
          latitude: lat,
          longitude: 127,
          accuracyMeters: 10,
          source: 'test',
          capturedAt: DateTime.utc(2026, 9, 12, hour),
        ),
);

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
  testWidgets('route connects valid capture locations in time order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineRouteMap(
            scraps: [
              scrap('Later', 15, 37.6),
              scrap('Unknown', 12, 0, located: false),
              scrap('Earlier', 9, 37.5),
              scrap('Invalid', 10, 100),
            ],
            tileProvider: _Tiles(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines
        .single;
    expect(line.points.map((p) => p.latitude), [37.5, 37.6]);
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(2),
    );
    expect(
      find.text('2 locations · Capture order · 2 without location'),
      findsOneWidget,
    );
    expect(find.byType(RichAttributionWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one location needs no route line and empty dates explain missing locations',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineRouteMap(
              scraps: [scrap('Only', 9, 37.5)],
              tileProvider: _Tiles(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PolylineLayer), findsNothing);
      expect(find.byType(MarkerLayer), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TimelineRouteMap(scraps: [])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No recorded locations on this date.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
