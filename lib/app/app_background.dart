import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/background_store.dart';
import '../state/app_controller.dart';
import 'design/ambient_background.dart';
import 'design/background.dart';

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
      builder: (context, focused, child) => AmbientBackground(
        animate: animate && focused,
        style: style,
        image: style == BackgroundStyle.image ? backgroundImageProvider(path) : null,
        dim: dim,
        child: child,
      ),
    );
  }
}
