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
    return AmbientBackground(
      animate: animate,
      style: style,
      image: style == BackgroundStyle.image ? backgroundImageProvider(path) : null,
      dim: dim,
      child: child,
    );
  }
}
