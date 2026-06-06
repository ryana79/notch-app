#!/bin/bash
# Upload Developer ID signing + notarization secrets to GitHub for trusted DMG releases.
#
# Prerequisites:
#   1. Create "Developer ID Application" at https://developer.apple.com/account/resources/certificates/list
#   2. Export the cert as .p12 from Keychain Access (include private key)
#   3. Create an app-specific password at https://appleid.apple.com/account/manage
#
# Usage:
#   CERT_P12_PATH=~/Desktop/DeveloperID.p12 \
#   P12_PASSWORD='your-p12-password' \
#   APPLE_ID='you@email.com' \
#   APPLE_APP_SPECIFIC_PASSWORD='xxxx-xxxx-xxxx-xxxx' \
#   ./scripts/setup-github-signing-secrets.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-ryana79/notch-app}"

require() {
  if [[ -z "${!1:-}" ]]; then
    echo "Missing $1. See script header for usage." >&2
    exit 1
  fi
}

require CERT_P12_PATH
require P12_PASSWORD
require APPLE_ID
require APPLE_APP_SPECIFIC_PASSWORD

if [[ ! -f "$CERT_P12_PATH" ]]; then
  echo "Certificate not found: $CERT_P12_PATH" >&2
  exit 1
fi

TEAM_ID="${DEVELOPMENT_TEAM_ID:-}"
if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' \
    | sed -n 's/.*(\([^)]*\)).*/\1/p' \
    | head -1)"
fi
if [[ -z "$TEAM_ID" ]]; then
  echo "Could not detect team ID. Set DEVELOPMENT_TEAM_ID=W497L7TLW7" >&2
  exit 1
fi

echo "Encoding certificate..."
BUILD_CERTIFICATE_BASE64="$(base64 < "$CERT_P12_PATH" | tr -d '\n')"

echo "Setting GitHub secrets for $REPO..."
gh secret set BUILD_CERTIFICATE_BASE64 --body "$BUILD_CERTIFICATE_BASE64" --repo "$REPO"
gh secret set P12_PASSWORD --body "$P12_PASSWORD" --repo "$REPO"
gh secret set KEYCHAIN_PASSWORD --body "${KEYCHAIN_PASSWORD:-notchpro-ci}" --repo "$REPO"
gh secret set APPLE_ID --body "$APPLE_ID" --repo "$REPO"
gh secret set APPLE_APP_SPECIFIC_PASSWORD --body "$APPLE_APP_SPECIFIC_PASSWORD" --repo "$REPO"
gh variable set DEVELOPMENT_TEAM_ID --body "$TEAM_ID" --repo "$REPO"

echo ""
echo "Done. Push a tag (e.g. git tag v1.0.10 && git push origin v1.0.10) to publish a notarized DMG."
