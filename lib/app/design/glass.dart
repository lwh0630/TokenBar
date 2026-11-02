import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

// --------------------------------------------------------------- painters

/// Soft drop shadow drawn only *outside* the shape, so it does not darken the
/// translucent glass above it.
class _OuterShadowPainter extends CustomPainter {
  const _OuterShadowPainter({required this.radius, required this.color, required this.elevation});

  final double radius;
  final Color color;

  /// 0 = flat, 1 = resting card, 2 = floating chrome.
  final double elevation;

  @override
  void paint(Canvas canvas, Size size) {
    if (elevation <= 0 || size.isEmpty) return;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final blur = 10.0 + elevation * 14;
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(blur * 3 + 40))
      ..addRRect(rrect);
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRRect(
      rrect.shift(Offset(0, 4.0 + elevation * 6)),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
    // Tight contact shadow.
    canvas.drawRRect(
      rrect.shift(const Offset(0, 1)),
      Paint()
        ..color = color.withValues(alpha: color.a * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.color != color || old.elevation != elevation;
}

/// 1 px gradient edge (bright top-left, dim bottom-right) plus a faint inner
/// sheen along the top: the "lit glass" rim.
class _RimPainter extends CustomPainter {
  const _RimPainter({
    required this.radius,
    required this.light,
    required this.dark,
    required this.sheen,
    required this.focus,
  });

  final double radius;
  final Color light;
  final Color dark;
  final Color sheen;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius - 0.5));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, dark],
        ).createShader(rect),
    );
    // Sheen: a short bright gradient hugging the top edge, inside the rim.
    final sheenRect = Rect.fromLTWH(0, 0, size.width, (size.height * 0.5).clamp(0, 56));
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [sheen, sheen.withValues(alpha: 0)],
        ).createShader(sheenRect),
    );
    canvas.restore();
    final f = focus;
    if (f != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(radius - 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = f,
      );
    }
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius ||
      old.light != light ||
      old.dark != dark ||
      old.sheen != sheen ||
      old.focus != focus;
}

// ----------------------------------------------------------------- surface

/// Chrome-level glass: a real backdrop blur under a translucent fill, a lit
/// rim and a floating shadow. Use it sparingly (sidebar, dialogs, popovers,
/// tray panel): every instance costs a blur pass. Scrolling content should use
/// [GlassCard] instead.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = Rd.xl,
    this.blur = 26,
    this.padding,
    this.fill,
    this.elevation = 2,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final shape = BorderRadius.circular(radius);
    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);
    return CustomPaint(
      painter: _OuterShadowPainter(radius: radius, color: g.shadow, elevation: elevation),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            foregroundPainter: _RimPainter(
              radius: radius,
              light: g.edgeLight,
              dark: g.edgeDark,
              sheen: g.highlight.withValues(alpha: g.highlight.a * 0.35),
              focus: null,
            ),
            child: ColoredBox(
              color: fill ?? g.fillStrong,
              child: Material(type: MaterialType.transparency, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- pressable

/// Hover / press / keyboard-focus behavior shared by every interactive glass
/// element: a pointer cursor, a tiny press-down scale and a focus ring, with no
/// Material ripple.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.scale = 0.985,
    this.cursor,
    this.focusNode,
    this.semanticLabel,
  });

  /// Builds the content for the current interaction state.
  final Widget Function(BuildContext context, bool hovered, bool pressed, bool focused) builder;
  final VoidCallback? onTap;
  final double scale;
  final MouseCursor? cursor;
  final FocusNode? focusNode;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(context, _hovered, _pressed, _focused);
    if (!_enabled) return content;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        mouseCursor: widget.cursor ?? SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? widget.scale : 1,
            duration: Motion.of(context, Motion.fast),
            curve: Motion.curve,
            child: content,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- card

/// Card-level glass without a per-card backdrop blur (cheap in long scrolling
/// lists): translucent fill, lit rim and soft shadow. When [onTap] is set it
/// lifts on hover and dips on press.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.radius = Rd.lg,
    this.clip = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final accent = Theme.of(context).colorScheme.primary;
    Widget build(bool hovered, bool focused) {
      final shape = BorderRadius.circular(radius);
      Widget content = padding == null ? child : Padding(padding: padding!, child: child);
      if (clip) content = ClipRRect(borderRadius: shape, child: content);
      return AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        curve: Motion.curve,
        transform: Matrix4.translationValues(0, hovered ? -1.5 : 0, 0),
        child: CustomPaint(
          painter: _OuterShadowPainter(
            radius: radius,
            color: g.shadow,
            elevation: hovered ? 1.6 : 1,
          ),
          foregroundPainter: _RimPainter(
            radius: radius,
            light: hovered ? g.edgeLight : g.edgeLight.withValues(alpha: g.edgeLight.a * 0.85),
            dark: g.edgeDark,
            sheen: g.highlight.withValues(alpha: g.highlight.a * (hovered ? 0.3 : 0.18)),
            focus: focused ? accent.withValues(alpha: 0.7) : null,
          ),
          child: ClipRRect(
            borderRadius: shape,
            // A transparent Material under the tinted fill keeps ListTile / InkWell
            // children from painting their ink behind the fill.
            child: ColoredBox(
              color: g.fill,
              child: Material(type: MaterialType.transparency, child: content),
            ),
          ),
        ),
      );
    }

    if (onTap == null) return build(false, false);
    return Pressable(
      onTap: onTap,
      builder: (context, hovered, _, focused) => build(hovered, focused),
    );
  }
}

// ------------------------------------------------------------------ button

enum GlassButtonKind { primary, secondary, ghost }

/// Capsule-ish button: gradient accent for the main action, glass for the
/// secondary one, and a bare hover-only variant.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.kind = GlassButtonKind.secondary,
    this.compact = false,
  }) : assert(label != null || icon != null);

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final GlassButtonKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final enabled = onPressed != null;
    return Pressable(
      onTap: onPressed,
      scale: 0.97,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered, pressed, focused) {
        final primary = kind == GlassButtonKind.primary;
        final ghost = kind == GlassButtonKind.ghost;
        final fg = primary ? Colors.white : theme.colorScheme.onSurface;
        final height = compact ? 30.0 : 38.0;
        final radius = height / 2.4;
        BoxDecoration decoration;
        if (primary) {
          decoration = BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent, g.accentEnd],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: hovered ? 0.45 : 0.3),
                blurRadius: hovered ? 18 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          );
        } else {
          decoration = BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: ghost
                ? (hovered ? g.fillSubtle : Colors.transparent)
                : (hovered ? g.fillStrong : g.fill),
            border: ghost && !focused ? null : Border.all(color: focused ? accent : g.hairline),
          );
        }
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) Icon(icon, size: compact ? 15 : 17, color: fg),
            if (icon != null && label != null) const SizedBox(width: 6),
            if (label != null)
              Text(
                label!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: fg,
                  fontSize: compact ? 12.5 : 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        );
        return Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            curve: Motion.curve,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : (compact ? 12 : 16)),
            decoration: decoration,
            child: Center(widthFactor: 1, child: content),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------ small pieces

/// Small tinted capsule (plan names, status).
class GlassChip extends StatelessWidget {
  const GlassChip(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: tint, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Small section caption above a group of cards.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x1, Sp.x3, Sp.x1, Sp.x2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelLarge?.copyWith(
                color: muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                fontSize: 12,
              ),
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ dialog

/// Glass dialog with the same slots as [AlertDialog].
class GlassDialog extends StatelessWidget {
  const GlassDialog({super.key, this.title, this.content, this.actions = const [], this.width});

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: Sp.x6),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width ?? 560),
        child: GlassSurface(
          radius: Rd.xl,
          blur: 32,
          elevation: 2,
          fill: context.glass.isDark ? const Color(0xB31A1D27) : const Color(0xD9FFFFFF),
          padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x6, Sp.x6, Sp.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                DefaultTextStyle(
                  style: theme.textTheme.titleLarge!.copyWith(color: theme.colorScheme.onSurface),
                  child: title!,
                ),
              if (title != null && content != null) const SizedBox(height: Sp.x4),
              if (content != null)
                Flexible(
                  child: SingleChildScrollView(
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      child: content!,
                    ),
                  ),
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Sp.x5),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Sp.x2,
                  runSpacing: Sp.x2,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Like `showDialog`, with a soft blurred scrim and a scale-fade entrance.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: Motion.of(context, Motion.base),
    pageBuilder: (ctx, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.curve);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5 * curved.value, sigmaY: 5 * curved.value),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        ),
      );
    },
  );
}
