import 'package:flutter/material.dart';

/// Design tokens of the "liquid glass" look: spacing, radii, motion and the
/// semantic glass colors. Everything visual in the app derives from here and
/// from [AppTheme]; do not sprinkle raw `Color(0x...)` values in widgets.

/// 4-pt spacing grid.
abstract final class Sp {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
}

/// Corner radii.
abstract final class Rd {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
}

/// Motion: one curve, three speeds.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
  static const Curve curve = Curves.easeOutCubic;

  /// Zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

/// Semantic colors of the glass surfaces for one brightness.
@immutable
class GlassColors extends ThemeExtension<GlassColors> {
  const GlassColors({
    required this.brightness,
    required this.base,
    required this.panel,
    required this.glowA,
    required this.glowB,
    required this.glowC,
    required this.fill,
    required this.fillStrong,
    required this.fillSubtle,
    required this.highlight,
    required this.edgeLight,
    required this.edgeDark,
    required this.hairline,
    required this.shadow,
    required this.accentEnd,
  });

  final Brightness brightness;

  /// Window background below the ambient glow.
  final Color base;

  /// Opaque surface for things that cannot be translucent (dropdown menus).
  final Color panel;

  /// Ambient light blobs behind the glass.
  final Color glowA;
  final Color glowB;
  final Color glowC;

  /// Cards: translucent, no blur of their own.
  final Color fill;

  /// Chrome (sidebar, dialogs, popovers): sits on a real backdrop blur.
  final Color fillStrong;

  /// Inset areas inside a surface (inputs, hovered rows).
  final Color fillSubtle;

  /// Top-edge sheen of a surface.
  final Color highlight;

  /// Gradient border: bright at the top-left, dim at the bottom-right.
  final Color edgeLight;
  final Color edgeDark;
  final Color hairline;
  final Color shadow;

  /// Second stop of the accent gradient (the first is the primary color).
  final Color accentEnd;

  bool get isDark => brightness == Brightness.dark;

  static const light = GlassColors(
    brightness: Brightness.light,
    base: Color(0xFFEDEFF6),
    panel: Color(0xFFF8F9FC),
    glowA: Color(0xFF7AA7FF),
    glowB: Color(0xFFB69CFF),
    glowC: Color(0xFF7FE3D2),
    fill: Color(0xA8FFFFFF),
    fillStrong: Color(0xB8FFFFFF),
    fillSubtle: Color(0x0F101828),
    highlight: Color(0xCCFFFFFF),
    edgeLight: Color(0xE6FFFFFF),
    edgeDark: Color(0x14101828),
    hairline: Color(0x14101828),
    shadow: Color(0x1A1B2A4E),
    accentEnd: Color(0xFF5E5CE6),
  );

  static const dark = GlassColors(
    brightness: Brightness.dark,
    base: Color(0xFF0D0F16),
    panel: Color(0xFF1A1D27),
    glowA: Color(0xFF3B6BFF),
    glowB: Color(0xFF8A5BFF),
    glowC: Color(0xFF14B8A6),
    fill: Color(0x14FFFFFF),
    fillStrong: Color(0x1FFFFFFF),
    fillSubtle: Color(0x14FFFFFF),
    highlight: Color(0x26FFFFFF),
    edgeLight: Color(0x38FFFFFF),
    edgeDark: Color(0x0AFFFFFF),
    hairline: Color(0x1FFFFFFF),
    shadow: Color(0x66000000),
    accentEnd: Color(0xFF7D7BFF),
  );

  static GlassColors of(Brightness b) => b == Brightness.dark ? dark : light;

  @override
  GlassColors copyWith({Brightness? brightness}) => of(brightness ?? this.brightness);

  @override
  GlassColors lerp(GlassColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension GlassContext on BuildContext {
  /// Glass colors of the current theme (falls back to the brightness default
  /// when a test builds a plain [ThemeData]).
  GlassColors get glass {
    final theme = Theme.of(this);
    return theme.extension<GlassColors>() ?? GlassColors.of(theme.brightness);
  }
}
