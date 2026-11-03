import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'background.dart';
import 'tokens.dart';

/// The bottom-most layer of the window: a calm base color with three large,
/// soft light blobs that drift very slowly. They give the glass surfaces above
/// something to blur and refract.
///
/// Set [animate] to false (tests, reduced motion) to freeze the blobs.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    this.animate = true,
    this.style = BackgroundStyle.aurora,
    this.image,
    this.dim = 0.45,
    this.child,
  });

  final bool animate;

  /// Gradient preset, or [BackgroundStyle.image] together with [image].
  final BackgroundStyle style;

  /// Picture for [BackgroundStyle.image]; without it the default gradient shows.
  final ImageProvider? image;

  /// Strength (0..0.85) of the theme-colored veil laid over the picture so the
  /// glass text stays readable.
  final double dim;

  final Widget? child;

  bool get _showsImage => style == BackgroundStyle.image && image != null;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with WidgetsBindingObserver {
  /// One drift cycle. The motion is so slow (a few pixels per second at the fastest)
  /// that repainting twice a second looks identical to 60 fps, while every step costs a
  /// re-blur of all the glass above, so keep it rare.
  static const _cycle = Duration(seconds: 90);
  static const _step = Duration(milliseconds: 500);

  final ValueNotifier<double> _phase = ValueNotifier(0);

  /// A plain timer instead of a `Ticker`: a ticker asks for a frame on every vsync
  /// (60 wake-ups a second) just to find out that nothing needs painting yet.
  Timer? _timer;
  final Stopwatch _running = Stopwatch();
  Duration _banked = Duration.zero; // drift time accumulated before the last pause
  bool _reduceMotion = false;
  bool _visible = true;
  _BlobSprites? _sprites;

  /// The blobs are rendered once per palette (see [_BlobSprites]); a drift step only draws them.
  _BlobSprites _spritesFor(BackgroundPalette palette, bool isDark) {
    final current = _sprites;
    if (current != null && current.palette == palette && current.isDark == isDark) return current;
    current?.dispose();
    return _sprites = _BlobSprites.render(palette, isDark);
  }

  void _onTick(Timer _) {
    final ms = (_banked + _running.elapsed).inMilliseconds;
    _phase.value = (ms % _cycle.inMilliseconds) / _cycle.inMilliseconds;
  }

  void _sync() {
    final shouldRun = widget.animate && !_reduceMotion && _visible && !widget._showsImage;
    if (shouldRun == (_timer != null)) return;
    if (shouldRun) {
      _running.start();
      _timer = Timer.periodic(_step, _onTick);
    } else {
      _timer!.cancel();
      _timer = null;
      _banked += _running.elapsed;
      _running
        ..stop()
        ..reset();
    }
  }

  static bool _isVisible(AppLifecycleState? state) =>
      state != AppLifecycleState.hidden && state != AppLifecycleState.paused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(AmbientBackground old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = _isVisible(state);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _phase.dispose();
    _sprites?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.glass;
    final palette = BackgroundPalette.of(widget.style, colors);
    final sprites = _spritesFor(palette, colors.isDark);
    // The background lives in its own layer so a drift step never repaints the app.
    final Widget background = widget._showsImage
        ? Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: palette.base),
              Image(
                image: widget.image!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // A missing / unreadable file falls back to the gradient.
                errorBuilder: (_, _, _) => CustomPaint(
                  painter: _AmbientPainter(palette, sprites, _phase),
                  size: Size.infinite,
                ),
              ),
              ColoredBox(
                color: (colors.isDark ? Colors.black : Colors.white).withValues(
                  alpha: widget.dim.clamp(0.0, 0.85),
                ),
              ),
            ],
          )
        : CustomPaint(painter: _AmbientPainter(palette, sprites, _phase), size: Size.infinite);
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: background),
        widget.child ?? const SizedBox.shrink(),
      ],
    );
  }
}

/// The three light blobs, each pre-rendered once into a small soft radial-gradient image.
///
/// Drawing a fresh `RadialGradient` shader every drift step looks harmless but is not:
/// with Impeller on Windows (OpenGL ES) every gradient paint kept hundreds of megabytes of
/// native memory alive, so the app grew to several GB within seconds and the growth was
/// proportional to the number of repaints (a window resize repaints on every frame).
/// Scaling a cached image is a plain textured quad and costs nothing, so never go back to
/// creating gradient shaders inside `paint`.
class _BlobSprites {
  _BlobSprites._(this.palette, this.isDark, this.a, this.b, this.c);

  /// Edge length of one sprite in pixels. The gradient is smooth, so it scales up cleanly.
  static const int size = 256;

  factory _BlobSprites.render(BackgroundPalette palette, bool isDark) {
    final strength = isDark ? 0.42 : 0.5;
    return _BlobSprites._(
      palette,
      isDark,
      _blob(palette.a, strength),
      _blob(palette.b, strength),
      _blob(palette.c, strength),
    );
  }

  static ui.Image _blob(Color color, double strength) {
    const half = size / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & const Size.square(size * 1.0),
      Paint()
        ..shader = ui.Gradient.radial(const Offset(half, half), half, [
          color.withValues(alpha: strength),
          color.withValues(alpha: 0),
        ]),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }

  final BackgroundPalette palette;
  final bool isDark;
  final ui.Image a;
  final ui.Image b;
  final ui.Image c;

  void dispose() {
    a.dispose();
    b.dispose();
    c.dispose();
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.palette, this.sprites, this.t) : super(repaint: t);

  final BackgroundPalette palette;
  final _BlobSprites sprites;
  final ValueListenable<double> t;

  static final Paint _spritePaint = Paint()..filterQuality = FilterQuality.low;
  static const Rect _source = Rect.fromLTWH(0, 0, 256, 256);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.base);
    if (size.isEmpty) return;
    final phase = t.value * 2 * math.pi;
    final reach = math.max(size.width, size.height);

    void blob(ui.Image image, double x, double y, double radius, double dx, double dy, double p) {
      final center = Offset(
        size.width * (x + dx * math.sin(phase + p)),
        size.height * (y + dy * math.cos(phase * 1.0 + p)),
      );
      final r = reach * radius;
      canvas.drawImageRect(
        image,
        _source,
        Rect.fromCircle(center: center, radius: r),
        _spritePaint,
      );
    }

    blob(sprites.a, 0.12, 0.08, 0.55, 0.05, 0.04, 0);
    blob(sprites.b, 0.92, 0.28, 0.5, 0.04, 0.06, 2.1);
    blob(sprites.c, 0.5, 1.02, 0.55, 0.06, 0.03, 4.2);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.palette != palette || old.sprites != sprites;
}
