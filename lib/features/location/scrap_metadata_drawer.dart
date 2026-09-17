// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/design/scrapnote_tokens.dart';
import '../../domain/scrap.dart';

class ScrapMetadataDrawer extends StatelessWidget {
  const ScrapMetadataDrawer({
    required this.scrap,
    this.locationSaving = false,
    this.onRetryLocation,
    this.onSetManualLocation,
    this.onOpenLocationSettings,
    super.key,
  });

  final Scrap? scrap;
  final bool locationSaving;
  final VoidCallback? onRetryLocation;
  final ValueChanged<ScrapLocation>? onSetManualLocation;
  final VoidCallback? onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final current = scrap;
    return Drawer(
      width: math.min(360, MediaQuery.sizeOf(context).width),
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
                            value: location.source == 'manual'
                                ? '수동 지정'
                                : '±${location.accuracyMeters.toStringAsFixed(0)} m',
                          ),
                          _MetadataRow(
                            label: 'SOURCE',
                            value: location.source == 'manual'
                                ? 'Manual'
                                : location.source,
                          ),
                          _MetadataRow(
                            label: 'CAPTURED',
                            value: _date(location.capturedAt),
                          ),
                          const SizedBox(height: ScrapnoteTokens.space2),
                          _LocationActions(
                            saving: locationSaving,
                            onRetry: onRetryLocation,
                            onManual: onSetManualLocation == null
                                ? null
                                : () => _openManualLocation(context, location),
                            onOpenSettings: onOpenLocationSettings,
                          ),
                        ] else ...<Widget>[
                          const _NoLocationState(),
                          const SizedBox(height: ScrapnoteTokens.space4),
                          _LocationActions(
                            saving: locationSaving,
                            onRetry: onRetryLocation,
                            onManual: onSetManualLocation == null
                                ? null
                                : () => _openManualLocation(context, null),
                            onOpenSettings: onOpenLocationSettings,
                          ),
                        ],
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

  Future<void> _openManualLocation(
    BuildContext context,
    ScrapLocation? initial,
  ) async {
    final location = await showFDialog<ScrapLocation>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        semanticsLabel: '수동 위치 지정',
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 440),
        builder: (context, style) => _ManualLocationForm(initial: initial),
      ),
    );
    if (location != null) onSetManualLocation?.call(location);
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
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            FLucideIcons.locateOff,
            size: 18,
            color: ScrapnoteTokens.signalOrange,
          ),
        ),
        SizedBox(width: ScrapnoteTokens.space2),
        Expanded(
          child: Text(
            '위치가 저장되지 않았습니다. 기기 위치를 다시 요청하거나 위도와 경도를 직접 입력할 수 있습니다.',
            style: TextStyle(
              color: ScrapnoteTokens.charcoalSoft,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationActions extends StatelessWidget {
  const _LocationActions({
    required this.saving,
    required this.onRetry,
    required this.onManual,
    required this.onOpenSettings,
  });

  final bool saving;
  final VoidCallback? onRetry;
  final VoidCallback? onManual;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FButton(
          onPress: saving ? null : onRetry,
          prefix: const Icon(FLucideIcons.locateFixed),
          child: Text(saving ? '위치 저장 중…' : '현재 위치 다시 기록'),
        ),
        const SizedBox(height: ScrapnoteTokens.space2),
        FButton(
          variant: FButtonVariant.outline,
          onPress: saving ? null : onManual,
          prefix: const Icon(FLucideIcons.mapPinPen),
          child: const Text('수동 위치 지정'),
        ),
        const SizedBox(height: ScrapnoteTokens.space2),
        FButton(
          variant: FButtonVariant.ghost,
          onPress: saving ? null : onOpenSettings,
          prefix: const Icon(FLucideIcons.settings),
          child: const Text('앱 설정에서 위치 허용'),
        ),
      ],
    );
  }
}

class _ManualLocationForm extends StatefulWidget {
  const _ManualLocationForm({required this.initial});

  final ScrapLocation? initial;

  @override
  State<_ManualLocationForm> createState() => _ManualLocationFormState();
}

class _ManualLocationFormState extends State<_ManualLocationForm> {
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  String? _latitudeError;
  String? _longitudeError;

  @override
  void initState() {
    super.initState();
    _latitude = TextEditingController(
      text: widget.initial?.latitude.toStringAsFixed(6) ?? '',
    );
    _longitude = TextEditingController(
      text: widget.initial?.longitude.toStringAsFixed(6) ?? '',
    );
  }

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _save() {
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    final latitudeValid =
        latitude != null &&
        latitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90;
    final longitudeValid =
        longitude != null &&
        longitude.isFinite &&
        longitude >= -180 &&
        longitude <= 180;
    setState(() {
      _latitudeError = latitudeValid ? null : '−90에서 90 사이의 위도를 입력해 주세요.';
      _longitudeError = longitudeValid ? null : '−180에서 180 사이의 경도를 입력해 주세요.';
    });
    if (!latitudeValid || !longitudeValid) return;
    Navigator.of(context).pop(
      ScrapLocation(
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: 0,
        source: 'manual',
        capturedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ScrapnoteTokens.space5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '수동 위치 지정',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: ScrapnoteTokens.space2),
          const Text(
            '지도 앱에서 복사한 위도와 경도를 입력하세요. 위치 출처는 “Manual”로 기록됩니다.',
            style: TextStyle(
              color: ScrapnoteTokens.mutedInk,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: ScrapnoteTokens.space4),
          FTextField(
            label: const Text('위도'),
            hint: '37.566500',
            control: FTextFieldControl.managed(controller: _latitude),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            textInputAction: TextInputAction.next,
            error: _latitudeError == null ? null : Text(_latitudeError!),
          ),
          const SizedBox(height: ScrapnoteTokens.space3),
          FTextField(
            label: const Text('경도'),
            hint: '126.978000',
            control: FTextFieldControl.managed(controller: _longitude),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _save(),
            error: _longitudeError == null ? null : Text(_longitudeError!),
          ),
          const SizedBox(height: ScrapnoteTokens.space5),
          Row(
            children: <Widget>[
              Expanded(
                child: FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: ScrapnoteTokens.space2),
              Expanded(
                child: FButton(onPress: _save, child: const Text('위치 저장')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
