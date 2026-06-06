# NotchPro auto-update setup (Sparkle + GitHub Pages)

## One-time GitHub configuration

### 1. Repository secret (required for releases)

Copy the contents of `ed_private_key.txt` (generated locally; never commit this file) into:

**GitHub → Settings → Secrets and variables → Actions → New repository secret**

- Name: `PRIVATE_SPARKLE_KEY`
- Value: entire contents of `ed_private_key.txt` (one line, base64)

If you need to regenerate keys:

```bash
# Install Sparkle generate_keys (or build from Sparkle repo), then:
generate_keys --account notchpro
generate_keys --account notchpro -x Configuration/sparkle/ed_private_key.txt
```

### 2. GitHub Pages

**Settings → Pages → Build and deployment → Source: GitHub Actions**

The `Deploy static content to Pages` workflow publishes `updater/appcast.xml` to:

`https://raw.githubusercontent.com/ryana79/notch-app/main/updater/appcast.xml`

### 3. Optional signing secrets (smoother installs)

For signed/notarized DMGs (no Gatekeeper warnings), add:

- `BUILD_CERTIFICATE_BASE64` — Developer ID Application `.p12`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_ID` — Apple ID email used for notarization
- `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password from appleid.apple.com
- `DEVELOPMENT_TEAM_ID` (repository variable)

Without these, CI builds with ad-hoc signing (first open: Right-click → Open once).

## Publishing a release

**Actions → Publish NotchPro Release → Run workflow**

- Enter version, e.g. `1.0.1`
- Optional build number (defaults to run number)

Or push a tag:

```bash
git tag v1.0.1
git push origin v1.0.1
```

This will:

1. Build `NotchPro.dmg`
2. Create a GitHub Release
3. Update `updater/appcast.xml` (signed with Sparkle)
4. Deploy the appcast to GitHub Pages

## Share with friends

Send the latest release link:

**https://github.com/ryana79/notch-app/releases/latest**

They download `NotchPro.dmg`, drag to Applications, open once (Right-click → Open if macOS blocks it). Future updates appear in **NotchPro → Settings → About → Check for Updates** automatically.
