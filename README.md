# NotchPro

A fast, secure MacBook notch overlay — music, calendar, weather, and productivity tools in one minimal bar.

NotchPro is an independent fork rebuilt for performance, security, and daily productivity. It does **not** auto-update from third-party servers.

## Features

- **Music live activity** — album art, spectrum bars, and track info flanking the notch
- **Calendar & weather** — next event pill and temperature at a glance
- **Clipboard history** — secure, blocks passwords and API keys (⌘⇧C)
- **Focus timer, system stats, shelf** — optional productivity widgets
- **Layout presets** — Balanced (recommended), Minimal, Media, Productivity, Utility

## Install

```bash
./scripts/install-notchpro.sh
```

Builds Release, installs to `/Applications/NotchPro.app`, and launches one clean instance.

## Develop

```bash
open NotchPro.xcodeproj
```

Select the **NotchPro** scheme and press **Cmd+R**. Do not run Debug and the installed app at the same time.

Manual build:

```bash
xcodebuild -project NotchPro.xcodeproj -scheme NotchPro -configuration Release -destination 'platform=macOS' build
```

## Quit completely

- Menu bar ⚡ → **Quit NotchPro**
- Red **Quit** pill in the expanded notch header
- Right-click the notch → **Quit NotchPro**

This terminates NotchPro and its media helper processes.

## License

GPL-3.0 — see [LICENSE](./LICENSE). Original upstream inspiration noted in [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES).
