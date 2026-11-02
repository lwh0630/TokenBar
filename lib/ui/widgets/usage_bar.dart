import 'package:flutter/material.dart';

import '../../app/design/tokens.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';

/// Thin remaining-quota bar with an optional linear-pace marker.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.remaining, this.paceRemaining, this.height = 6});

  /// 0-100.
  final double remaining;

  /// Where remaining would be on a perfectly linear pace (0-100).
  final double? paceRemaining;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = quotaColor(remaining, theme.brightness);
    final track = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fillFraction = remaining.clamp(0, 100) / 100;
        final pace = paceRemaining;
        return SizedBox(
          height: height + 4,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fillFraction),
                duration: Motion.of(context, Motion.slow + const Duration(milliseconds: 120)),
                curve: Motion.curve,
                builder: (context, f, _) => Container(
                  height: height,
                  width: f * width,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color.withValues(alpha: 0.78), color]),
                    borderRadius: BorderRadius.circular(height),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: 6,
                        spreadRadius: -1,
                      ),
                    ],
                  ),
                ),
              ),
              if (pace != null)
                Positioned(
                  left: (pace.clamp(0, 100) / 100 * width - 1).clamp(0, width - 2),
                  child: Tooltip(
                    message: l.paceTooltip(pace.round()),
                    child: Container(
                      width: 2,
                      height: height + 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
