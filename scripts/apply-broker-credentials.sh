#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.broker-secrets.env"
PLIST="$ROOT/NotchPro/Resources/BrokerCredentials.plist"
EXAMPLE="$ROOT/NotchPro/Resources/BrokerCredentials.example.plist"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — copy from .broker-secrets.env.example" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

[[ -f "$PLIST" ]] || cp "$EXAMPLE" "$PLIST"

/usr/libexec/PlistBuddy -c "Set :SchwabClientID '${SCHWAB_CLIENT_ID:-}'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :SchwabClientSecret '${SCHWAB_CLIENT_SECRET:-}'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :SchwabTokenProxyURL '${SCHWAB_TOKEN_PROXY_URL:-}'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :BrokerProxyAPIKey '${NOTCHPRO_BROKER_PROXY_KEY:-}'" "$PLIST"
if /usr/libexec/PlistBuddy -c "Print :PortfolioInsightsProxyURL" "$PLIST" &>/dev/null; then
  /usr/libexec/PlistBuddy -c "Set :PortfolioInsightsProxyURL 'https://broker-proxy.vercel.app/api/portfolio/insights'" "$PLIST"
else
  /usr/libexec/PlistBuddy -c "Add :PortfolioInsightsProxyURL string 'https://broker-proxy.vercel.app/api/portfolio/insights'" "$PLIST"
fi
/usr/libexec/PlistBuddy -c "Set :WebullAppKey '${WEBULL_APP_KEY:-}'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :WebullAppSecret '${WEBULL_APP_SECRET:-}'" "$PLIST"

echo "Wrote BrokerCredentials.plist"
echo "  Schwab:  $([[ -n "${SCHWAB_CLIENT_ID:-}" ]] && echo configured || echo missing)"
echo "  Proxy:   $([[ -n "${SCHWAB_TOKEN_PROXY_URL:-}" ]] && echo "${SCHWAB_TOKEN_PROXY_URL}" || echo none)"
echo "  Webull:  $([[ -n "${WEBULL_APP_KEY:-}" ]] && echo configured || echo missing)"
