import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/glass.dart' show GlassMotionTracker;
import 'design/tokens.dart';

/// Liquid-glass design system on top of Material 3.
///
/// Material supplies behavior (focus, text fields, menus); everything the user
/// sees is restyled here: translucent surfaces over an ambient background,
/// hairline lit edges, generous radii, no ink ripples. The glass colors live in
/// the [GlassColors] theme extension (see `design/tokens.dart`); the widgets
/// that need real blur are in `design/glass.dart`.
class AppTheme {
  static const _accentLight = Color(0xFF0A74FF);
  static const _accentDark = Color(0xFF4C93FF);

  static const radius = 14.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Per-platform UI font. Flutter's own default on Windows is Segoe UI, which
  /// has no Han glyphs, so CJK text would fall back to whatever font the engine
  /// picks first (often not Microsoft YaHei). Naming the CJK fonts explicitly
  /// keeps Chinese text consistent.
  static ({String? family, List<String> fallback}) get fonts {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return (
          family: 'Segoe UI',
          fallback: const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI Emoji'],
        );
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return (
          family: '.AppleSystemUIFont',
          fallback: const ['PingFang SC', 'Hiragino Sans GB', 'Apple Color Emoji'],
        );
      case TargetPlatform.linux:
        return (
          family: null,
          fallback: const [
            'Noto Sans CJK SC',
            'Noto Sans SC',
            'WenQuanYi Micro Hei',
            'Source Han Sans SC',
          ],
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return (family: null, fallback: const ['Noto Sans CJK SC', 'Noto Sans SC']);
    }
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final g = GlassColors.of(brightness);
    final accent = isDark ? _accentDark : _accentLight;

    final onSurface = isDark ? const Color(0xFFF1F3FA) : const Color(0xFF151822);
    final muted = isDark ? const Color(0xFF9BA1B4) : const Color(0xFF626879);

    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
      primary: accent,
      onPrimary: Colors.white,
      surface: g.panel,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      surfaceContainerLowest: g.base,
      surfaceContainerLow: g.panel,
      surfaceContainer: g.panel,
      surfaceContainerHigh: isDark ? const Color(0xFF242836) : const Color(0xFFEEF0F7),
      surfaceContainerHighest: isDark ? const Color(0xFF2C3142) : const Color(0xFFE6E9F2),
      secondaryContainer: accent.withValues(alpha: isDark ? 0.24 : 0.12),
      onSecondaryContainer: accent,
      outline: muted,
      outlineVariant: g.hairline,
      error: isDark ? const Color(0xFFFF6B61) : const Color(0xFFE5392E),
    );

    final f = fonts;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: f.family,
      fontFamilyFallback: f.fallback,
    );

    // Calm, tight type scale: heavier titles, slightly negative tracking on
    // the large sizes, regular body.
    final text = base.textTheme
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.2,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 14.5),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13.5, height: 1.35),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.35),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(fontSize: 11, letterSpacing: 0.1),
        )
        .apply(bodyColor: onSurface, displayColor: onSurface);

    final r12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md));
    final tooltipFill = isDark ? const Color(0xE62A2F40) : const Color(0xE61B1F2C);

    return base.copyWith(
      extensions: [g],
      textTheme: text,
      // The ambient background lives under the Navigator (see main.dart), so
      // pages are transparent. [canvasColor] stays opaque: dropdown menus and
      // other Material surfaces that cannot be translucent use it.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: g.panel,
      dividerColor: g.hairline,
      dividerTheme: DividerThemeData(color: g.hairline, space: 1, thickness: 1),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: onSurface.withValues(alpha: 0.05),
      focusColor: accent.withValues(alpha: 0.12),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _GlassPageTransitions(),
          TargetPlatform.iOS: _GlassPageTransitions(),
          TargetPlatform.windows: _GlassPageTransitions(),
          TargetPlatform.macOS: _GlassPageTransitions(),
          TargetPlatform.linux: _GlassPageTransitions(),
          TargetPlatform.fuchsia: _GlassPageTransitions(),
        },
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: Colors.transparent,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.28),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: g.fill,
        surfaceTintColor: Colors.transparent,
        shadowColor: g.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.lg),
          side: BorderSide(color: g.hairline),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 60,
        // A transparent bar would otherwise be judged "dark" and get light status
        // icons on the light theme.
        systemOverlayStyle: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        foregroundColor: onSurface,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        shape: r12,
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.x4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xF21A1D27) : const Color(0xF2FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.xl),
          side: BorderSide(color: g.hairline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xF21A1D27) : const Color(0xF2FFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.xl)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xF21F2230) : const Color(0xF5FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: g.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          side: BorderSide(color: g.hairline),
        ),
        textStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tooltipFill,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: const Color(0xFF8FB8FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md)),
        insetPadding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: accent.withValues(alpha: isDark ? 0.28 : 0.14),
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? accent : muted, size: 22),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: g.fillSubtle,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: g.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: g.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: muted),
        helperStyle: text.bodySmall?.copyWith(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: r12,
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x3),
          textStyle: text.titleSmall,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: r12,
          side: BorderSide(color: g.hairline),
          backgroundColor: g.fill,
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x3),
          textStyle: text.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: r12, textStyle: text.titleSmall),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.sm + 2)),
          foregroundColor: onSurface,
          hoverColor: onSurface.withValues(alpha: 0.07),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            text.labelLarge?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: g.hairline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.sm + 2)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? accent.withValues(alpha: isDark ? 0.3 : 0.15)
                : g.fillSubtle,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: g.hairline),
        backgroundColor: g.fillSubtle,
        selectedColor: accent.withValues(alpha: isDark ? 0.3 : 0.15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: text.labelLarge?.copyWith(fontSize: 12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (isDark ? const Color(0xFF32D74B) : const Color(0xFF34C759))
              : (isDark ? const Color(0xFF454A5C) : const Color(0xFFD3D6E0)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(6),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => onSurface.withValues(alpha: s.contains(WidgetState.hovered) ? 0.42 : 0.24),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(color: tooltipFill, borderRadius: BorderRadius.circular(Rd.sm)),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}

/// Horizontal carousel: the pushed page slides in from the right while the page
/// below slides out to the left, so the two never overlap.
///
/// Deliberately no fade: pages are full of `BackdropFilter` glass, and a
/// `FadeTransition` wraps the page in an offscreen layer that (a) costs a full-screen
/// copy per frame and (b) makes every blur sample an empty backdrop, so the glass
/// looked wrong during the transition and popped into place when it ended. Plain
/// translations keep the page's layers cached and the blur correct.
class _GlassPageTransitions extends PageTransitionsBuilder {
  const _GlassPageTransitions();

  static final _enter = Tween(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: Motion.curve));
  static final _exit = Tween(
    begin: Offset.zero,
    end: const Offset(-1, 0),
  ).chain(CurveTween(curve: Motion.curve));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return child;
    return GlassMotionTracker(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: SlideTransition(
        position: animation.drive(_enter),
        child: SlideTransition(
          position: secondaryAnimation.drive(_exit),
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

/// Remaining-quota color: green > 50%, amber > 20%, red otherwise.
/// Uses the Apple system palette.
Color quotaColor(double remaining, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  if (remaining > 50) return dark ? const Color(0xFF30D158) : const Color(0xFF34C759);
  if (remaining > 20) return dark ? const Color(0xFFFFD60A) : const Color(0xFFFF9500);
  return dark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
}

/// Colors for stacked series (models / windows), in a fixed order. Ten
/// distinct hues of similar lightness that read on both light and dark cards;
/// neighbours differ strongly so the first few series are easy to tell apart.
const seriesPalette = [
  Color(0xFF3B82F6), // blue
  Color(0xFF10B981), // emerald
  Color(0xFFF59E0B), // amber
  Color(0xFF8B5CF6), // violet
  Color(0xFFF43F5E), // rose
  Color(0xFF06B6D4), // cyan
  Color(0xFFF97316), // orange
  Color(0xFF6366F1), // indigo
  Color(0xFFEC4899), // pink
  Color(0xFF84CC16), // lime
];

/// Color of the merged "Other" series.
const seriesOtherColor = Color(0xFF9CA3AF);
