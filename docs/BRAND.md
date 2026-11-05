# Codex Meter identity

Codex Meter keeps its existing name. Two parallel, slightly overlapping rings
represent Codex and Claude Code sharing one native macOS application. Open arcs
suggest meters without inventing a quota reading. The mark has no numerals,
needles, ticks or vendor logos and should remain readable at small sizes.

The identity is an original geometric construction in
[`scripts/make-icon.swift`](../scripts/make-icon.swift). One set of ring centers,
radii, arc angles and stroke widths generates the app icon, transparent mark and
repository artwork. The app icon retains the macOS tile inset and corner shape.

| Color | Hex | Use |
| --- | --- | --- |
| Teal | `#48CCB0` | Codex ring |
| Terracotta | `#EF9B78` | Claude ring |
| Ink | `#192426` | Banner and icon background |
| Warm paper | `#F6F2E9` | Banner typography |
| Muted sage | `#87928B` at 34% | Unfilled ring tracks |

The project wordmark uses native system typography. The tagline is
**Both limits. One glance.** The supporting line is
**Codex + Claude Code · Native for macOS**. The rings are abstract brand artwork,
not a screenshot or an illustration of actual account usage. The two colors
identify services; they do not indicate quota or connection status.

## Export

From the repository root on macOS with Xcode Command Line Tools:

```sh
xcrun swift -module-cache-path .build/module-cache scripts/make-icon.swift --brand .
xcrun swift -module-cache-path .build/module-cache scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
```

| Asset | Size | Purpose |
| --- | --- | --- |
| `assets/banner.svg`, `assets/banner.png` | 1600 × 540 | SVG README header and PNG export |
| `assets/social-preview.png` | 1600 × 800 | Repository social preview |
| `assets/logo.svg`, `assets/logo.png` | 1024 × 1024, transparent | Standalone project mark |
| `Resources/MeterMark.svg`, `Resources/MeterMark.png` | Vector / 256 × 256, transparent | Native panel header |
| Generated `AppIcon.iconset` | Standard 16–1024 px exports | Application icon |
| Generated `.build/brand-preview.png` | 960 × 430 | 16/32/64/128 px review on light and dark backgrounds |

PNG artwork is drawn directly with AppKit at its export size; the social preview
is laid out on its own canvas, not cropped from a raster banner. SVG files retain
the geometry and editable text. Font rendering can vary with the macOS/system
font version; no downloaded fonts, renderer packages or network access are used.

All current brand artwork is code-native vector construction and falls under the
repository's MIT license. No AI-generated bitmap is used. Historical versions
of the repository contained a different AI-generated banner; its original
provenance remains in Git history. The retained
[`assets/banner-prompt.md`](../assets/banner-prompt.md) path records this replacement.
