# Security Policy

## Reporting a Vulnerability

To report a security issue in NotchPro, open a [GitHub Security Advisory](https://github.com/ryana79/notch-app/security/advisories/new) on this repository.

## First launch: "NotchPro cannot be opened" or password prompts

NotchPro releases are signed for local use. macOS Gatekeeper may warn the app is from an unidentified developer the first time you install it.

**To open the first time:**

1. Download the DMG from [Releases](https://github.com/ryana79/notch-app/releases).
2. Drag NotchPro to Applications.
3. **Right-click** (or Control-click) NotchPro in Applications → **Open** → confirm **Open** once.
4. After that, double-click works normally.

**Password prompts:** NotchPro stores broker tokens in the macOS Keychain. If you reinstall or update from a build with a different signature, macOS may ask for your login keychain password once per stored credential. This is normal Keychain behavior, not malware.

**Reduce prompts:** Install from the official GitHub release DMG and avoid mixing local Xcode builds with the release app.

## What NotchPro accesses

- **Keychain** — Schwab/Webull tokens and optional personal API keys only on your Mac
- **Calendar & Reminders** — optional, for the calendar widget
- **Camera** — optional, for the mirror feature
- **Accessibility** — optional, for media controls and notch gestures
- **Network** — weather, portfolio brokers, Yahoo Finance news, and the shared AI insights proxy

Broker secrets for the shared NotchPro build are embedded at compile time; user OAuth tokens never leave your Mac except to Schwab/Webull APIs.
