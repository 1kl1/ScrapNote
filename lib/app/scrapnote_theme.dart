import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../core/design/scrapnote_tokens.dart';

/// The single light theme used by the desktop-first Scrapnote workbench.
abstract final class ScrapnoteTheme {
  static final FColors colors = FColors(
    brightness: Brightness.light,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    barrier: ScrapnoteTokens.modalBarrier,
    background: ScrapnoteTokens.paper,
    foreground: ScrapnoteTokens.charcoal,
    primary: ScrapnoteTokens.signalOrange,
    primaryForeground: ScrapnoteTokens.paperRaised,
    secondary: ScrapnoteTokens.paperSunken,
    secondaryForeground: ScrapnoteTokens.charcoal,
    muted: ScrapnoteTokens.paperSunken,
    mutedForeground: ScrapnoteTokens.mutedInk,
    destructive: ScrapnoteTokens.destructive,
    destructiveForeground: ScrapnoteTokens.paperRaised,
    error: ScrapnoteTokens.destructive,
    errorForeground: ScrapnoteTokens.paperRaised,
    card: ScrapnoteTokens.paperRaised,
    border: ScrapnoteTokens.rule,
    hoverDarken: 0.035,
    disabledOpacity: 0.48,
  );

  static final FThemeData foruiTheme = _createForuiTheme();
  static final ThemeData materialTheme = _createMaterialTheme();

  /// Shared document text styling, separate from compact form inputs.
  static final FTextFieldStyle editorTextFieldStyle = foruiTheme
      .textFieldStyles
      .md
      .copyWith(
        border: FVariants(InputBorder.none, variants: const {}),
        color: FVariants(ScrapnoteTokens.paper, variants: const {}),
        contentTextStyle: FVariants(
          const TextStyle(
            color: ScrapnoteTokens.charcoal,
            fontSize: 15,
            height: 1.6,
          ),
          variants: const {},
        ),
        contentPadding: const EdgeInsetsGeometryDelta.value(
          EdgeInsets.symmetric(vertical: 8),
        ),
      );

  static FThemeData _createForuiTheme() {
    final body = FTypeface.inherit(
      colors: colors,
      touch: false,
      fontFamily: '.AppleSystemUIFont',
      fontFamilyFallback: const <String>[
        'Segoe UI',
        'Roboto',
        'Noto Sans',
        FTypeface.defaultFontFamily,
      ],
    );
    final display = body.copyWith(
      lg: body.lg.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.25),
      xl: body.xl.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.35),
      xl2: body.xl2.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.55),
      xl3: body.xl3.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.75),
    );
    final typography = FTypography(display: display, body: body);
    final inheritedStyle = FStyle.inherit(
      colors: colors,
      typography: typography,
      touch: false,
    );
    const tight = BorderRadius.all(
      Radius.circular(ScrapnoteTokens.radiusTight),
    );
    const regular = BorderRadius.all(Radius.circular(ScrapnoteTokens.radius));
    const large = BorderRadius.all(
      Radius.circular(ScrapnoteTokens.radiusLarge),
    );

    final style = FStyle(
      formFieldStyle: inheritedStyle.formFieldStyle,
      focusedOutlineStyle: const FFocusedOutlineStyle(
        color: ScrapnoteTokens.focusHalo,
        borderRadius: regular,
        width: 2,
        spacing: 2,
      ),
      iconStyle: inheritedStyle.iconStyle.copyWith(
        color: ScrapnoteTokens.charcoal,
        size: 18,
      ),
      sizes: inheritedStyle.sizes,
      tappableStyle: inheritedStyle.tappableStyle,
      borderRadius: const FBorderRadius(
        xs2: tight,
        xs: tight,
        sm: regular,
        md: regular,
        lg: large,
        xl: large,
        xl2: large,
        xl3: large,
      ),
      borderWidth: ScrapnoteTokens.hairline,
      pagePadding: EdgeInsets.zero,
      shadow: const <BoxShadow>[],
    );

    return FThemeData(
      debugLabel: 'Scrapnote Warm Paper Desktop',
      colors: colors,
      typography: typography,
      style: style,
      touch: false,
    );
  }

  static ThemeData _createMaterialTheme() {
    final base = foruiTheme.toApproximateMaterialTheme();
    return base.copyWith(
      scaffoldBackgroundColor: ScrapnoteTokens.paper,
      canvasColor: ScrapnoteTokens.paper,
      dividerColor: ScrapnoteTokens.rule,
      disabledColor: ScrapnoteTokens.mutedInk.withValues(alpha: 0.48),
      focusColor: ScrapnoteTokens.signalOrangeWash,
      hoverColor: ScrapnoteTokens.charcoal.withValues(alpha: 0.035),
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: ScrapnoteTokens.signalOrange,
        selectionColor: ScrapnoteTokens.selectionOrangeWash,
        selectionHandleColor: ScrapnoteTokens.signalOrange,
      ),
      dividerTheme: const DividerThemeData(
        color: ScrapnoteTokens.rule,
        thickness: ScrapnoteTokens.hairline,
        space: ScrapnoteTokens.hairline,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(ScrapnoteTokens.radiusTight),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return ScrapnoteTokens.charcoalSoft;
          }
          return ScrapnoteTokens.ruleStrong;
        }),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 700),
        showDuration: Duration(seconds: 3),
        decoration: BoxDecoration(
          color: ScrapnoteTokens.charcoal,
          borderRadius: BorderRadius.all(
            Radius.circular(ScrapnoteTokens.radiusTight),
          ),
        ),
        textStyle: TextStyle(
          color: ScrapnoteTokens.paperRaised,
          fontSize: 12,
          height: 1.25,
        ),
      ),
    );
  }
}
