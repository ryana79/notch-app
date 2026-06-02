# NotchPro

A fast, secure MacBook notch overlay — music, calendar, weather, and productivity tools in one minimal bar.

NotchPro is an independent fork rebuilt for performance, security, and daily productivity.

## Install (for friends)

Download the latest release and drag **NotchPro** to **Applications**:

**https://github.com/ryana79/notch-app/releases/latest**

If macOS blocks the app the first time: **Right-click NotchPro → Open**.

Updates install automatically (Sparkle). You can also use **Settings → About → Check for Updates**.

## Develop locally

```bash
./scripts/install-notchpro.sh
```

Builds Release, installs to `/Applications/NotchPro.app`, and launches one clean instance.

```bash
open NotchPro.xcodeproj
```

Select the **NotchPro** scheme and press **Cmd+R**. Do not run Debug and the installed app at the same time.

## Publish a new version (maintainer)

1. One-time setup: [Configuration/sparkle/SETUP.md](Configuration/sparkle/SETUP.md)  
   - Add GitHub secret `PRIVATE_SPARKLE_KEY`  
   - Enable **GitHub Pages** (source: GitHub Actions)

2. Run **Actions → Publish NotchPro Release** with a version (e.g. `1.0.1`), or:

```bash
git tag v1.0.1
git push origin v1.0.1
```

3. Share the releases link above with friends.

## Quit completely

- Menu bar ⚡ → **Quit NotchPro**
- Red **Quit** pill in the expanded notch header
- Right-click the notch → **Quit NotchPro**

## License

GPL-3.0 — see [LICENSE](./LICENSE). Original upstream inspiration noted in [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES).
