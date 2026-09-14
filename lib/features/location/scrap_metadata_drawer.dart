// Hallmark · component: metadata drawer · genre: modern-minimal
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/design/scrapnote_tokens.dart';
import '../../domain/scrap.dart';

class ScrapMetadataDrawer extends StatelessWidget {
  const ScrapMetadataDrawer({required this.scrap, super.key});

  final Scrap? scrap;

  @override
  Widget build(BuildContext context) {
    final current = scrap;
    return Drawer(
      width: 360,
      backgroundColor: ScrapnoteTokens.paperRaised,
      elevation: 0,
      shape: const Border(left: BorderSide(color: ScrapnoteTokens.rule)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: ScrapnoteTokens.tabStripHeight,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: ScrapnoteTokens.space4),
                  const Expanded(
                    child: Text(
                      'SCRAP INFO',
                      style: TextStyle(
                        color: ScrapnoteTokens.charcoal,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close information',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(FLucideIcons.x, size: 16),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: ScrapnoteTokens.rule),
            Expanded(
              child: current == null
                  ? const _UnsavedLocationState()
                  : ListView(
                      padding: const EdgeInsets.all(ScrapnoteTokens.space4),
                      children: <Widget>[
                        _MetadataRow(label: 'ID', value: current.id),
                        _MetadataRow(
                          label: 'CREATED',
                          value: _date(current.createdAt),
                        ),
                        _MetadataRow(
                          label: 'MODIFIED',
                          value: _date(current.updatedAt),
                        ),
                        _MetadataRow(
                          label: 'TIME ZONE',
                          value: current.timezoneName ?? 'Not recorded',
                        ),
                        _MetadataRow(
                          label: 'UTC OFFSET',
                          value: _offset(current.utcOffsetMinutes),
                        ),
                        const SizedBox(height: ScrapnoteTokens.space4),
                        const Divider(height: 1, color: ScrapnoteTokens.rule),
                        const SizedBox(height: ScrapnoteTokens.space4),
                        if (current.location case final location?) ...<Widget>[
                          SizedBox(
                            height: 240,
                            child: ClipRect(
                              child: _LocationMap(location: location),
                            ),
                          ),
                          const SizedBox(height: ScrapnoteTokens.space4),
                          _MetadataRow(
                            label: 'LATITUDE',
                            value: location.latitude.toStringAsFixed(6),
                          ),
                          _MetadataRow(
                            label: 'LONGITUDE',
                            value: location.longitude.toStringAsFixed(6),
                          ),
                          _MetadataRow(
                            label: 'ACCURACY',
                            value:
                                '±${location.accuracyMeters.toStringAsFixed(0)} m',
                          ),
                          _MetadataRow(label: 'SOURCE', value: location.source),
                          _MetadataRow(
                            label: 'CAPTURED',
                            value: _date(location.capturedAt),
                          ),
                        ] else
                          const _NoLocationState(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());

  static String _offset(int? minutes) {
    if (minutes == null) {
      return 'Not recorded';
    }
    final sign = minutes < 0 ? '−' : '+';
    final absolute = minutes.abs();
    return 'UTC$sign${(absolute ~/ 60).toString().padLeft(2, '0')}:'
        '${(absolute % 60).toString().padLeft(2, '0')}';
  }
}

class _LocationMap extends StatelessWidget {
  const _LocationMap({required this.location});

  final ScrapLocation location;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(location.latitude, location.longitude);
    return FlutterMap(
      options: MapOptions(initialCenter: point, initialZoom: 15),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.scrapnote',
        ),
        MarkerLayer(
          markers: <Marker>[
            Marker(
              point: point,
              width: 44,
              height: 44,
              child: const Icon(
                FLucideIcons.mapPin,
                color: ScrapnoteTokens.signalOrange,
                size: 30,
                semanticLabel: 'Saved location',
              ),
            ),
          ],
        ),
        const RichAttributionWidget(
          showFlutterMapAttribution: false,
          attributions: <SourceAttribution>[
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ScrapnoteTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: ScrapnoteTokens.mutedInk,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: ScrapnoteTokens.space1),
          SelectableText(
            value,
            style: const TextStyle(
              color: ScrapnoteTokens.charcoal,
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsavedLocationState extends StatelessWidget {
  const _UnsavedLocationState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(ScrapnoteTokens.space4),
      child: Text(
        'Save this Scrap once to capture and display its location.',
        style: TextStyle(
          color: ScrapnoteTokens.mutedInk,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}

class _NoLocationState extends StatelessWidget {
  const _NoLocationState();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'No location was recorded. Location Services may be unavailable or permission may have been declined.',
      style: TextStyle(
        color: ScrapnoteTokens.mutedInk,
        fontSize: 13,
        height: 1.5,
      ),
    );
  }
}
