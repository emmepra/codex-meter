# Visual assets

- `MeterMark.svg` and `MeterMark.png`: Codex Meter's independent twin-ring project mark, constructed from circles and arcs in `scripts/make-icon.swift`. The PNG is a transparent 256 × 256 export for the panel header. Neither ring is an OpenAI or Anthropic logo.
- The same geometry draws the application icon on a warm charcoal tile. The existing build command produces all standard macOS icon sizes and packages `AppIcon.icns`. Header and repository artwork can be regenerated offline with `xcrun swift scripts/make-icon.swift --brand .` from the repository root.
- See [the brand guide](../docs/BRAND.md) for colors, exports and provenance. These assets contain no quota values or account data.

## Sparkle

Sparkle 2.10.0 is bundled for signed in-app updates. Its license is included as `Contents/Resources/Sparkle-LICENSE`. Source: https://github.com/sparkle-project/Sparkle. `Sparkle-public-key.txt` contains only the public update-verification key.
