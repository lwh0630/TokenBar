# Provider logos

The SVG files in this folder are named after TokenBar provider ids
(`<provider id>.svg`) and are used by `lib/ui/widgets/provider_badge.dart`.

## Source

Copied unmodified from the CodexBar repository:

- `Sources/CodexBar/Resources/ProviderIcon-<name>.svg` (menu-bar logos), with
  the name mapped to the TokenBar id by `iconResourceName` in CodexBar's
  provider descriptors. Examples: `moonshot.svg` <- `ProviderIcon-kimi.svg`,
  `openai.svg` <- `ProviderIcon-codex.svg` (CodexBar uses the same logo for the
  OpenAI API provider).
- `claude.svg` <- `Sources/CodexBar/Resources/Brand-ProviderIcon-claude.svg`
  (the coloured brand version; drawn on a white tile).
- `copilot.svg` <- [`Sources/CodexBar/Resources/ProviderIcon-copilot.svg`](https://github.com/steipete/CodexBar/blob/5f93dc3068b3bee3f8753f3772614cc2949c335d/Sources/CodexBar/Resources/ProviderIcon-copilot.svg).

Upstream: <https://github.com/steipete/CodexBar>, MIT License, Copyright (c) 2026
Peter Steinberger. The full MIT text is in the repository's `NOTICE.md`.

`mimo.svg` is copied unmodified from
[`nesszer/Win-CodexBar`](https://github.com/nesszer/Win-CodexBar/blob/v0.70.0/rust/assets/icons/ProviderIcon-mimo.svg),
MIT License, Copyright (c) 2025 Peter Steinberger; see `NOTICE.md`.

Files in this folder that have a coloured logo (`claude`, `aixy`, `futureagi`,
`sub2api`) keep their original colours; all other logos are single-colour and
are recoloured at runtime (see `providerColoredIconIds` in `provider_badge.dart`).

`ibmbob` has no logo here: the CodexBar SVG uses `<mask>` and gradients, which
the renderer does not support, so it keeps the initial-letter badge.

## Trademarks

The logos are trademarks of their respective owners. They are used only to
identify the corresponding services in this app. They do not imply
endorsement by, or affiliation with, those owners.
