import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/background_store.dart';
import '../state/app_controller.dart';
import 'design/ambient_background.dart';
import 'design/background.dart';
import 'design/glass.dart' show GlassCardBlur;

/// [AmbientBackground] wired to the user's background setting (gradient preset
/// or picture). Used for the main window and the tray panel.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.animate = true, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (style, path, dim) = context.select<AppController, (BackgroundStyle, String, double)>(
      (c) => (c.settings.background, c.settings.backgroundImage, c.settings.backgroundDim),
    );
    // The drift only runs while the window has focus: every drift step re-blurs all the
    // glass above it, and an unfocused window that sits still needs no frames at all.
    return ValueListenableBuilder<bool>(
      valueListenable: context.read<AppController>().desktop.focused,
      child: child,
      builder: (context, focused, child) {
        final image = style == BackgroundStyle.image ? backgroundImageProvider(path) : null;
        return AmbientBackground(
          animate: animate && focused,
          style: style,
          image: image,
          dim: dim,
          // Cards only blur what is behind them over a picture; the gradients are smooth
          // enough that a blur there would cost an offscreen pass per card for nothing.
          child: GlassCardBlur(blur: image == null ? 0 : 16, child: child!),
        );
      },
    );
  }
}
