import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/timeline/timeline_dial.dart';
import 'package:scrapnote/features/timeline/timeline_view.dart';

void main() {
  testWidgets(
    'groups a scrap by its capture date after the device time zone changes',
    (tester) async {
      final scrap = Scrap(
        id: 'travel-scrap',
        body: '# Across midnight\nSaved before midnight while travelling.',
        // 23:30 on September 4 at UTC-07:00 is already September 5 UTC and
        // September 5 in the test machine's Asia/Seoul time zone.
        createdAt: DateTime.utc(2026, 9, 5, 6, 30),
        updatedAt: DateTime.utc(2026, 9, 10, 6, 30),
        localDate: '2026-09-04',
        utcOffsetMinutes: -7 * 60,
        timezoneName: 'PDT',
      );

      await tester.pumpWidget(
        _TimelineHarness(
          scraps: <Scrap>[scrap],
          selectedDate: DateTime(2026, 9, 4),
        ),
      );

      expect(find.text('Across midnight'), findsOneWidget);
      expect(find.text('23:30'), findsOneWidget);
      expect(find.text('Friday · 4 September 2026'), findsOneWidget);
      expect(find.text('1 scrap'), findsOneWidget);
      final dial = tester.widget<TimelineDial>(find.byType(TimelineDial));
      expect(dial.markedDates, contains(DateTime(2026, 9, 4)));
      expect(dial.markedDates, isNot(contains(DateTime(2026, 9, 5))));

      await tester.pumpWidget(
        _TimelineHarness(
          scraps: <Scrap>[scrap],
          selectedDate: DateTime(2026, 9, 5),
        ),
      );

      expect(find.text('Across midnight'), findsNothing);
      expect(find.text('No scraps on this date.'), findsOneWidget);
      expect(find.text('Saturday · 5 September 2026'), findsOneWidget);
    },
  );

  testWidgets('keeps content chronological and the dial clipped', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final later = Scrap(
      id: 'later',
      body: '# Later scrap\nSecond in time.',
      createdAt: DateTime(2026, 9, 4, 16, 45),
      updatedAt: DateTime(2026, 9, 4, 16, 45),
      localDate: '2026-09-04',
    );
    final earlier = Scrap(
      id: 'earlier',
      body: '# Earlier scrap\nFirst in time.',
      createdAt: DateTime(2026, 9, 4, 8, 15),
      updatedAt: DateTime(2026, 9, 4, 8, 15),
      localDate: '2026-09-04',
    );

    await tester.pumpWidget(
      _TimelineHarness(
        scraps: <Scrap>[later, earlier],
        selectedDate: DateTime(2026, 9, 4),
      ),
    );

    expect(
      tester.getTopLeft(find.text('Earlier scrap')).dy,
      lessThan(tester.getTopLeft(find.text('Later scrap')).dy),
    );
    expect(find.text('LOCATION TRAIL'), findsNothing);
    expect(find.textContaining('saved locations'), findsNothing);
    expect(find.byType(Card), findsNothing);

    final dialClip = find.byKey(TimelineView.dialClipKey);
    expect(dialClip, findsOneWidget);
    expect(tester.widget<Widget>(dialClip), isA<ClipRect>());
    expect(
      find.descendant(of: dialClip, matching: find.byType(TimelineDial)),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(dialClip).dy,
      greaterThan(tester.getTopLeft(find.text('Later scrap')).dy),
    );
  });

  testWidgets('renders local Markdown images and scrolls long entries', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 520);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final vault = Directory.systemTemp.createTempSync('timeline-image-');
    addTearDown(() => vault.deleteSync(recursive: true));
    final assets = Directory('${vault.path}/assets');
    assets.createSync(recursive: true);
    File('${assets.path}/pixel.png').writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=',
      ),
    );
    final longBody = List<String>.generate(
      36,
      (index) => 'Paragraph ${index + 1}: a timeline detail.',
    ).join('\n\n');
    final scrap = Scrap(
      id: 'image-scrap',
      body: '# Image scrap\n\n![pixel](../assets/pixel.png)\n\n$longBody',
      createdAt: DateTime.utc(2026, 9, 4, 8),
      updatedAt: DateTime.utc(2026, 9, 4, 9),
      localDate: '2026-09-04',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineView(
            vaultPath: vault.path,
            scraps: <Scrap>[scrap],
            selectedDate: DateTime(2026, 9, 4),
            onDateChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Paragraph 1: a timeline detail.'), findsOneWidget);
    expect(find.text('Paragraph 36: a timeline detail.'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
  });
}

class _TimelineHarness extends StatelessWidget {
  const _TimelineHarness({required this.scraps, required this.selectedDate});

  final List<Scrap> scraps;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: TimelineView(
          vaultPath: '/tmp/vault',
          scraps: scraps,
          selectedDate: selectedDate,
          onDateChanged: (_) {},
        ),
      ),
    );
  }
}
