#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/NotchPro/Resources/BrokerCredentials.plist"
EXAMPLE="$ROOT/NotchPro/Resources/BrokerCredentials.example.plist"

if [[ ! -f "$PLIST" ]]; then
  cp "$EXAMPLE" "$PLIST"
  echo "Created $PLIST from example."
fi

echo ""
echo "NotchPro shared broker setup (one-time — friends won't need to do this)"
echo "========================================================================"
echo ""
echo "Schwab: register ONE app at https://developer.schwab.com"
echo "  Callback URL: https://127.0.0.1:8765"
echo ""
read -r -p "Schwab Client ID: " SCHWAB_ID
read -r -s -p "Schwab Client Secret (hidden): " SCHWAB_SECRET
echo ""
read -r -p "Schwab token proxy URL (optional, recommended — leave blank for local-only): " SCHWAB_PROXY
read -r -s -p "Broker proxy API key (must match Vercel NOTCHPRO_BROKER_PROXY_KEY): " PROXY_KEY
echo ""
echo ""
echo "Webull: register ONE app at https://developer.webull.com"
read -r -p "Webull App Key: " WEBULL_KEY
read -r -s -p "Webull App Secret (hidden): " WEBULL_SECRET
echo ""

/usr/libexec/PlistBuddy -c "Set :SchwabClientID '$SCHWAB_ID'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :SchwabClientSecret '$SCHWAB_SECRET'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :SchwabTokenProxyURL '$SCHWAB_PROXY'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :BrokerProxyAPIKey '$PROXY_KEY'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :WebullAppKey '$WEBULL_KEY'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :WebullAppSecret '$WEBULL_SECRET'" "$PLIST"

echo ""
echo "Saved to BrokerCredentials.plist (gitignored)."
echo "Rebuild and share NotchPro.app — friends only tap Connect in Settings → Integrations."
echo ""
echo "Optional: deploy broker-proxy to Vercel for safer Schwab token exchange:"
echo "  cd broker-proxy && npx vercel"
