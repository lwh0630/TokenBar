import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/design/glass.dart';
import '../app/design/tokens.dart';
import '../services/desktop.dart';

/// Height of the unified title bar.
const double kTitleBarHeight = 40;

/// The main window's custom title bar and resize edges (the native title bar is
/// hidden, see [DesktopIntegration.init]).
///
/// The bar is transparent so the ambient background runs underneath it: it only
/// carries the app name, the drag area and (on Windows / Linux) the caption
/// buttons. macOS keeps its native traffic lights at the left.
class WindowChrome extends StatelessWidget {
  const WindowChrome({super.key, required this.desktop, required this.child});

  final DesktopIntegration desktop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!desktop.hasCustomChrome) return child;
    final content = Column(
      children: [
        _TitleBar(desktop: desktop),
        Expanded(child: child),
      ],
    );
    if (!desktop.needsResizeEdges) return content;
    return Stack(
      children: [
        content,
        // Undecorated GTK windows have no resize border of their own.
        ..._ResizeEdges.build(desktop),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.desktop});

  final DesktopIntegration desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return SizedBox(
      height: kTitleBarHeight,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => desktop.startDragging(),
              onDoubleTap: desktop.toggleMaximize,
              child: Padding(
                // Leave room for the macOS traffic lights.
                padding: EdgeInsets.only(left: mac ? 78 : Sp.x4),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.asset(
                        'assets/icon/tokenbar.png',
                        width: 18,
                        height: 18,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    const SizedBox(width: Sp.x2),
                    Text(
                      'TokenBar',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (desktop.drawsWindowButtons) _CaptionButtons(desktop: desktop),
        ],
      ),
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionButtons extends StatelessWidget {
  const _CaptionButtons({required this.desktop});

  final DesktopIntegration desktop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: Sp.x2),
      child: ValueListenableBuilder<bool>(
        valueListenable: desktop.maximized,
        builder: (context, maximized, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CaptionButton(glyph: _Glyph.minimize, onTap: desktop.minimizeWindow),
            _CaptionButton(
              glyph: maximized ? _Glyph.restore : _Glyph.maximize,
              onTap: desktop.toggleMaximize,
            ),
            _CaptionButton(glyph: _Glyph.close, onTap: desktop.closeWindow, danger: true),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({required this.glyph, required this.onTap, this.danger = false});

  final _Glyph glyph;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final fg = Theme.of(context).colorScheme.onSurface;
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      builder: (context, hovered, pressed, focused) {
        final red = danger && hovered;
        return AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          width: 40,
          height: 28,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.sm),
            color: red
                ? const Color(0xFFE5392E)
                : (hovered
                      ? g.fillSubtle.withValues(alpha: g.fillSubtle.a * 1.6)
                      : Colors.transparent),
          ),
          child: Center(
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _GlyphPainter(glyph, red ? Colors.white : fg.withValues(alpha: 0.85)),
            ),
          ),
        );
      },
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
      case _Glyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
            const Radius.circular(1.6),
          ),
          p,
        );
      case _Glyph.restore:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0.5, 2.5, size.width - 3, size.height - 3),
            const Radius.circular(1.4),
          ),
          p,
        );
        final back = Path()
          ..moveTo(2.8, 0.5)
          ..lineTo(size.width - 0.5, 0.5)
          ..lineTo(size.width - 0.5, size.height - 2.8);
        canvas.drawPath(back, p);
      case _Glyph.close:
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), p);
        canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

/// Invisible strips around the window that start a native resize drag.
abstract final class _ResizeEdges {
  static const double _edge = 5;
  static const double _corner = 10;

  static List<Widget> build(DesktopIntegration desktop) {
    Widget strip(
      WindowEdge edge,
      MouseCursor cursor, {
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
    }) => Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => desktop.startResizing(edge),
        ),
      ),
    );
    return [
      strip(
        WindowEdge.top,
        SystemMouseCursors.resizeUp,
        left: _corner,
        right: _corner,
        top: 0,
        height: _edge,
      ),
      strip(
        WindowEdge.bottom,
        SystemMouseCursors.resizeDown,
        left: _corner,
        right: _corner,
        bottom: 0,
        height: _edge,
      ),
      strip(
        WindowEdge.left,
        SystemMouseCursors.resizeLeft,
        left: 0,
        top: _corner,
        bottom: _corner,
        width: _edge,
      ),
      strip(
        WindowEdge.right,
        SystemMouseCursors.resizeRight,
        right: 0,
        top: _corner,
        bottom: _corner,
        width: _edge,
      ),
      strip(
        WindowEdge.topLeft,
        SystemMouseCursors.resizeUpLeft,
        left: 0,
        top: 0,
        width: _corner,
        height: _corner,
      ),
      strip(
        WindowEdge.topRight,
        SystemMouseCursors.resizeUpRight,
        right: 0,
        top: 0,
        width: _corner,
        height: _corner,
      ),
      strip(
        WindowEdge.bottomLeft,
        SystemMouseCursors.resizeDownLeft,
        left: 0,
        bottom: 0,
        width: _corner,
        height: _corner,
      ),
      strip(
        WindowEdge.bottomRight,
        SystemMouseCursors.resizeDownRight,
        right: 0,
        bottom: 0,
        width: _corner,
        height: _corner,
      ),
    ];
  }
}
