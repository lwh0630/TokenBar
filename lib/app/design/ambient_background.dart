import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The bottom-most layer of the window: a calm base color with three large,
/// soft light blobs that drift very slowly. They give the glass surfaces above
/// something to blur and refract.
///
/// Set [animate] to false (tests, reduced motion) to freeze the blobs.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, this.animate = true, this.child});

  final bool animate;
  final Widget? child;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 90),
  );

  bool _running = false;

  void _sync(bool reduceMotion) {
    final shouldRun = widget.animate && !reduceMotion;
    if (shouldRun == _running) return;
    _running = shouldRun;
    shouldRun ? _drift.repeat() : _drift.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  }

  @override
  void didUpdateWidget(AmbientBackground old) {
    super.didUpdateWidget(old);
    _sync(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.glass;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AmbientPainter(colors, _drift),
        child: widget.child ?? const SizedBox.expand(),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.colors, this.t) : super(repaint: t);

  final GlassColors colors;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.base);
    if (size.isEmpty) return;
    final phase = t.value * 2 * math.pi;
    final reach = math.max(size.width, size.height);
    final strength = colors.isDark ? 0.42 : 0.5;

    void blob(Color color, double x, double y, double radius, double dx, double dy, double p) {
      final center = Offset(
        size.width * (x + dx * math.sin(phase + p)),
        size.height * (y + dy * math.cos(phase * 1.0 + p)),
      );
      final r = reach * radius;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: strength),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, paint);
    }

    blob(colors.glowA, 0.12, 0.08, 0.55, 0.05, 0.04, 0);
    blob(colors.glowB, 0.92, 0.28, 0.5, 0.04, 0.06, 2.1);
    blob(colors.glowC, 0.5, 1.02, 0.55, 0.06, 0.03, 4.2);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.colors != colors;
}
