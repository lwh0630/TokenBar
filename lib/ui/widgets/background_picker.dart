import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/design/background.dart';
import '../../app/design/glass.dart';
import '../../app/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/background_store.dart';
import '../../state/app_controller.dart';

/// Settings control for the window background: gradient presets, plus a picture
/// of the user's own (not on the web, which has no local files).
class BackgroundPicker extends StatefulWidget {
  const BackgroundPicker({super.key});

  @override
  State<BackgroundPicker> createState() => _BackgroundPickerState();
}

class _BackgroundPickerState extends State<BackgroundPicker> {
  bool _busy = false;

  String _label(AppLocalizations l, BackgroundStyle s) => switch (s) {
    BackgroundStyle.aurora => l.backgroundAurora,
    BackgroundStyle.sunset => l.backgroundSunset,
    BackgroundStyle.ocean => l.backgroundOcean,
    BackgroundStyle.forest => l.backgroundForest,
    BackgroundStyle.graphite => l.backgroundGraphite,
    BackgroundStyle.image => l.backgroundImage,
  };

  Future<void> _pickImage() async {
    if (_busy) return;
    final c = context.read<AppController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = AppLocalizations.of(context).backgroundImageFailed;
    setState(() => _busy = true);
    try {
      final path = await pickBackgroundImage();
      if (path != null) {
        await c.updateSettings(
          c.settings.copyWith(background: BackgroundStyle.image, backgroundImage: path),
        );
      }
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage() async {
    final c = context.read<AppController>();
    final old = c.settings.backgroundImage;
    await c.updateSettings(
      c.settings.copyWith(background: BackgroundStyle.aurora, backgroundImage: ''),
    );
    await deleteBackgroundImage(old);
  }

  void _select(BackgroundStyle style) {
    final c = context.read<AppController>();
    if (style == BackgroundStyle.image && c.settings.backgroundImage.isEmpty) {
      _pickImage();
      return;
    }
    c.updateSettings(c.settings.copyWith(background: style));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = context.watch<AppController>();
    final s = c.settings;
    final styles = [
      ...BackgroundStyle.values.where((b) => b.isPreset),
      if (backgroundImageSupported) BackgroundStyle.image,
    ];
    final onImage = s.background == BackgroundStyle.image && s.backgroundImage.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x3),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.settingsBackground, style: theme.textTheme.bodyLarge),
            const SizedBox(height: Sp.x3),
            Wrap(
              spacing: Sp.x3,
              runSpacing: Sp.x3,
              children: [
                for (final style in styles)
                  _Swatch(
                    style: style,
                    label: _label(l, style),
                    selected: s.background == style,
                    imagePath: style == BackgroundStyle.image ? s.backgroundImage : '',
                    onTap: () => _select(style),
                  ),
              ],
            ),
            if (onImage) ...[
              const SizedBox(height: Sp.x4),
              Row(
                children: [
                  GlassButton(
                    compact: true,
                    icon: Icons.photo_library_outlined,
                    label: l.backgroundChangeImage,
                    onPressed: _busy ? null : _pickImage,
                  ),
                  const SizedBox(width: Sp.x2),
                  GlassButton(
                    compact: true,
                    kind: GlassButtonKind.ghost,
                    icon: Icons.delete_outline,
                    label: l.backgroundRemoveImage,
                    onPressed: _removeImage,
                  ),
                ],
              ),
              const SizedBox(height: Sp.x3),
              Text(l.backgroundDim, style: theme.textTheme.bodyMedium),
              Slider(
                value: s.backgroundDim.clamp(0.0, 0.85),
                max: 0.85,
                divisions: 17,
                label: '${(s.backgroundDim * 100).round()}%',
                onChanged: (v) => c.updateSettings(s.copyWith(backgroundDim: v)),
              ),
              Text(
                l.backgroundDimHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.style,
    required this.label,
    required this.selected,
    required this.imagePath,
    required this.onTap,
  });

  final BackgroundStyle style;
  final String label;
  final bool selected;
  final String imagePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = context.glass;
    final accent = theme.colorScheme.primary;
    final palette = BackgroundPalette.of(style, g);
    final image = style == BackgroundStyle.image ? backgroundImageProvider(imagePath) : null;
    const w = 88.0, h = 52.0;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hovered, pressed, focused) => SizedBox(
        width: w,
        child: Column(
          children: [
            AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              width: w,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Rd.md),
                border: Border.all(
                  color: selected ? accent : (hovered ? g.edgeLight : g.hairline),
                  width: selected ? 2 : 1,
                ),
                gradient: image == null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.alphaBlend(palette.a.withValues(alpha: 0.75), palette.base),
                          Color.alphaBlend(palette.b.withValues(alpha: 0.65), palette.base),
                          Color.alphaBlend(palette.c.withValues(alpha: 0.75), palette.base),
                        ],
                      )
                    : null,
                image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
              ),
              child: style == BackgroundStyle.image && image == null
                  ? Icon(Icons.add_photo_alternate_outlined, color: theme.colorScheme.onSurface)
                  : (selected
                        ? const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(3),
                              child: Icon(Icons.check_circle, size: 16, color: Colors.white),
                            ),
                          )
                        : null),
            ),
            const SizedBox(height: Sp.x1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected ? accent : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
