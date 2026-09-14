import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

import '../../core/design/scrapnote_tokens.dart';
import '../../domain/scrap.dart';

/// Recorded capture points joined chronologically; this is not road routing.
class TimelineRouteMap extends StatelessWidget {
  const TimelineRouteMap({required this.scraps, this.tileProvider, super.key});
  final List<Scrap> scraps;
  final TileProvider? tileProvider;

  static List<Scrap> locatedScraps(Iterable<Scrap> scraps) =>
      scraps.where((s) {
        final location = s.location;
        return location != null &&
            location.latitude.isFinite &&
            location.longitude.isFinite &&
            location.latitude.abs() <= 90 &&
            location.longitude.abs() <= 180;
      }).toList()..sort((a, b) {
        final order = a.createdAt.compareTo(b.createdAt);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });

  @override
  Widget build(BuildContext context) {
    final located = locatedScraps(scraps);
    if (located.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No recorded locations on this date.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final points = located
        .map((s) => LatLng(s.location!.latitude, s.location!.longitude))
        .toList();
    final distinct = points.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${located.length} locations · Capture order${scraps.length > located.length ? ' · ${scraps.length - located.length} without location' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: FlutterMap(
              key: ValueKey(
                points.map((p) => '${p.latitude},${p.longitude}').join(';'),
              ),
              options: MapOptions(
                initialCenter: points.first,
                initialZoom: 14,
                initialCameraFit: distinct.length < 2
                    ? null
                    : CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(points),
                        padding: const EdgeInsets.all(48),
                        maxZoom: 15,
                      ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.scrapnote',
                  tileProvider: tileProvider,
                ),
                if (points.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        color: ScrapnoteTokens.signalOrange,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < points.length; i++)
                      Marker(
                        point: points[i],
                        width: 36,
                        height: 36,
                        child: Tooltip(
                          message:
                              '${i + 1}. ${located[i].firstLineTitle}\n${DateFormat('HH:mm').format(_wallClock(located[i]))}',
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: ScrapnoteTokens.signalOrange,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  showFlutterMapAttribution: false,
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'Lines connect saved locations in time order.',
            style: TextStyle(fontSize: 11, color: ScrapnoteTokens.mutedInk),
          ),
        ),
      ],
    );
  }

  static DateTime _wallClock(Scrap scrap) => scrap.utcOffsetMinutes == null
      ? scrap.createdAt.toLocal()
      : scrap.createdAt.toUtc().add(Duration(minutes: scrap.utcOffsetMinutes!));
}
