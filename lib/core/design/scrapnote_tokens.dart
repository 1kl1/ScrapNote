// design-system: DESIGN.md · designed-as-app · Index-First editor shell
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5
// P—one persistent 48px activity rail anchors the product; H—hierarchy is
// encoded by panes and hairlines; E—orange remains a state signal only;
// M—every visible shell control performs navigation or vault selection.
// Hallmark · macrostructure: Index-First editor shell · nav: N4-derived icon rail

import 'package:flutter/material.dart';

/// Shared visual constants for Scrapnote's restrained desktop interface.
abstract final class ScrapnoteTokens {
  // Color is deliberately concentrated in the signal color. The remaining
  // surfaces are warm neutrals, like the faceplate of a Braun desk radio.
  static const Color paper = Color(0xFFF3F0E7);
  static const Color paperRaised = Color(0xFFFAF8F1);
  static const Color paperSunken = Color(0xFFEAE5D9);
  static const Color charcoal = Color(0xFF24231F);
  static const Color charcoalSoft = Color(0xFF4F4B43);
  static const Color mutedInk = Color(0xFF706B61);
  static const Color rule = Color(0xFFD3CDC0);
  static const Color ruleStrong = Color(0xFFAAA397);
  static const Color signalOrange = Color(0xFFB64717);
  static const Color signalOrangeWash = Color(0x1AB64717);
  static const Color selectionOrangeWash = Color(0x33B64717);
  static const Color modalBarrier = Color(0x6624231F);
  static const Color transparent = Colors.transparent;
  static const Color focusHalo = Color(0xFF8E3511);
  static const Color success = Color(0xFF35664A);
  static const Color destructive = Color(0xFFA53B2E);

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;

  static const double radiusTight = 2;
  static const double radius = 4;
  static const double radiusLarge = 6;
  static const double hairline = 1;
  static const double minimumHitTarget = 44;

  static const double activityRailWidth = 48;
  static const double explorerPaneWidth = 232;
  static const double tabStripHeight = 38;
  static const double statusLineHeight = 24;
  static const double syncStatusLineHeight = 32;

  // Compatibility aliases for feature workbenches that still use the original
  // token names. The rail no longer expands at wider breakpoints.
  static const double railWidth = activityRailWidth;
  static const double compactRailWidth = activityRailWidth;
  static const double explorerWidth = explorerPaneWidth;
  static const double tabBarHeight = tabStripHeight;
  static const double statusBarHeight = statusLineHeight;
  static const double screenHeaderHeight = tabStripHeight;
  static const double listPaneMinWidth = explorerPaneWidth;
  static const double listPaneMaxWidth = explorerPaneWidth;
  static const double notesFolderPaneWidth = explorerPaneWidth;
  static const double notesScrapPaneWidth = 304;

  static const Duration quickDuration = Duration(milliseconds: 100);
  static const Duration standardDuration = Duration(milliseconds: 160);
  static const Curve standardCurve = Curves.easeOutCubic;
}
