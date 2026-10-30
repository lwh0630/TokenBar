import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

/// Provider ids that have a logo at `assets/provider_icons/<id>.svg`
/// (copied from CodexBar, see `assets/provider_icons/README.md`).
///
/// Kept as a static set instead of probing the asset bundle at runtime so the
/// first frame already shows the right widget. `test/provider_icons_test.dart`
/// checks this set against the files on disk and against the registry.
const Set<String> providerIconIds = {
  'aerostack',
  'aiand',
  'aixy',
  'atlascloud',
  'bifrost',
  'chatbox',
  'chutes',
  'claude',
  'clawrouter',
  'codex',
  'copilot',
  'cosmic',
  'cursor',
  'deepinfra',
  'deepseek',
  'devpass',
  'elevenlabs',
  'exa',
  'fal',
  'fireworks',
  'flora',
  'futureagi',
  'gitkraken',
  'groq',
  'huggingface',
  'kimi',
  'linkup',
  'litellm',
  'llmproxy',
  'mimo',
  'minimax',
  'moonshot',
  'munito',
  'neuralwatt',
  'openai',
  'openrouter',
  'poe',
  'sailresearch',
  'sofya',
  'soniox',
  'sub2api',
  'synthetic',
  'tavily',
  'v0',
  'venice',
  'vercel',
  'warp',
  'xai',
  'xkiro',
  'zai',
  'zenmux',
};

/// Logos that keep their original brand colours (drawn on a white tile).
/// Every other logo in [providerIconIds] is a single-colour silhouette and is
/// recoloured to fit light and dark themes.
const Set<String> providerColoredIconIds = {'aixy', 'claude', 'futureagi', 'sub2api'};

/// Registered providers that deliberately keep the initial-letter badge
/// (no suitable single-colour logo: the CodexBar SVG relies on `<mask>` and
/// gradients).
const Set<String> providerIconFallbackIds = {'ibmbob'};

/// App-icon style badge: rounded square. Shows the provider logo when one is
/// bundled, otherwise a brand-colour gradient tile with the initial letter.
class ProviderBadge extends StatelessWidget {
  const ProviderBadge({super.key, required this.providerId, this.size = 32});

  final String providerId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final provider = ProviderRegistry.instance.byId(providerId);
    final brand = Color(provider?.brandColor ?? 0xFF64748B);
    final name = provider?.displayName ?? providerId;
    final shadow = [
      BoxShadow(
        color: brand.withValues(alpha: 0.28),
        blurRadius: size * 0.2,
        offset: Offset(0, size * 0.06),
      ),
    ];
    final radius = BorderRadius.circular(size * 0.28);

    if (providerIconIds.contains(providerId)) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final colored = providerColoredIconIds.contains(providerId);
      final iconSize = size * 0.62;
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colored ? Colors.white : brand.withValues(alpha: isDark ? 0.22 : 0.14),
          borderRadius: radius,
          border: colored ? Border.all(color: Colors.black.withValues(alpha: 0.08)) : null,
          boxShadow: shadow,
        ),
        child: SvgPicture.asset(
          'assets/provider_icons/$providerId.svg',
          width: iconSize,
          height: iconSize,
          semanticsLabel: name,
          colorFilter: colored
              ? null
              : ColorFilter.mode(_silhouetteColor(brand, isDark), BlendMode.srcIn),
        ),
      );
    }

    final hsl = HSLColor.fromColor(brand);
    final top = hsl.withLightness((hsl.lightness + 0.08).clamp(0, 1)).toColor();
    final bottom = hsl.withLightness((hsl.lightness - 0.08).clamp(0, 1)).toColor();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.5),
        boxShadow: shadow,
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.46,
          height: 1.1,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.25),
              offset: Offset(0, size * 0.02),
              blurRadius: size * 0.04,
            ),
          ],
        ),
      ),
    );
  }

  /// Brand colour for a silhouette logo, lifted (dark theme) or deepened
  /// (light theme) so white and black logos stay visible on the tile.
  static Color _silhouetteColor(Color brand, bool isDark) {
    final hsl = HSLColor.fromColor(brand);
    final lightness = isDark
        ? (hsl.lightness < 0.68 ? 0.68 : hsl.lightness)
        : (hsl.lightness > 0.38 ? 0.38 : hsl.lightness);
    return hsl.withLightness(lightness).toColor();
  }
}
