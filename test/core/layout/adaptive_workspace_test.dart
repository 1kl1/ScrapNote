import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_shell.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/core/layout/adaptive_workspace.dart';

void main() {
  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('navigation and editor actions fit width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saves = 0;
      final controller = TextEditingController(text: 'Keep my draft');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ScrapnoteTheme.materialTheme.copyWith(
            platform: TargetPlatform.android,
          ),
          home: ScrapnoteShell(
            section: ScrapnoteSection.scraps,
            onSectionChanged: (_) {},
            onChooseVault: () {},
            body: AdaptiveWorkspace(
              saving: false,
              onSave: () => saves++,
              onCreate: () {},
              onChooseImages: () {},
              listBuilder: (show) =>
                  FButton(onPress: show, child: const Text('Open item')),
              editor: TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('workspace-save')));
      expect(saves, 1);
      if (width < 600) {
        expect(find.byKey(const ValueKey('bottom-navigation')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('workspace-list-toggle')));
        await tester.pump();
        expect(find.text('Open item'), findsOneWidget);
        await tester.tap(find.text('Open item'));
        await tester.pump();
        expect(find.text('Keep my draft'), findsOneWidget);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('fold hinge and tabletop posture never cover active content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final feature in [
      const DisplayFeature(
        bounds: Rect.fromLTWH(410, 0, 20, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
      const DisplayFeature(
        bounds: Rect.fromLTWH(0, 440, 840, 20),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(840, 900),
              displayFeatures: [feature],
            ),
            child: ScrapnoteShell(
              section: ScrapnoteSection.scraps,
              onSectionChanged: (_) {},
              body: const Center(child: Text('Active content')),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(ScrapnoteShell.bodyKey));
      expect(rect.overlaps(feature.bounds), isFalse);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
