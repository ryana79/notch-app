#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.broker-secrets.env"
EXAMPLE="$ROOT/.broker-secrets.env.example"

echo "NotchPro broker setup"
echo "====================="
echo ""

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$EXAMPLE" "$ENV_FILE"
  PROXY_KEY="$(openssl rand -hex 32)"
  sed -i '' "s/REPLACE_WITH_openssl_rand_hex_32/$PROXY_KEY/" "$ENV_FILE"
  echo "Created .broker-secrets.env with a generated NOTCHPRO_BROKER_PROXY_KEY."
  echo ""
  echo "Open this file and add your Schwab + Webull keys:"
  echo "  open -e $ENV_FILE"
  echo ""
  echo "Then run this script again."
  exit 0
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

missing=0
[[ -n "${SCHWAB_CLIENT_ID:-}" ]] || { echo "Missing SCHWAB_CLIENT_ID in .broker-secrets.env"; missing=1; }
[[ -n "${SCHWAB_CLIENT_SECRET:-}" ]] || { echo "Missing SCHWAB_CLIENT_SECRET in .broker-secrets.env"; missing=1; }
[[ -n "${WEBULL_APP_KEY:-}" ]] || { echo "Missing WEBULL_APP_KEY in .broker-secrets.env"; missing=1; }
[[ -n "${WEBULL_APP_SECRET:-}" ]] || { echo "Missing WEBULL_APP_SECRET in .broker-secrets.env"; missing=1; }
[[ -n "${NOTCHPRO_BROKER_PROXY_KEY:-}" ]] || { echo "Missing NOTCHPRO_BROKER_PROXY_KEY in .broker-secrets.env"; missing=1; }

if [[ "$missing" -eq 1 ]]; then
  echo ""
  echo "Fill in .broker-secrets.env then re-run: ./scripts/setup-brokers-all.sh"
  exit 1
fi

if vercel whoami &>/dev/null; then
  echo "Deploying Schwab token proxy to Vercel..."
  "$ROOT/scripts/deploy-broker-proxy.sh"
else
  echo "Vercel not logged in — skipping proxy deploy."
  echo "  Create a token at https://vercel.com/account/tokens (in your browser), then:"
  echo "    export VERCEL_TOKEN='...'   # or: vercel login --token"
  echo "  Then: ./scripts/deploy-broker-proxy.sh"
  echo ""
  echo "Continuing with local Schwab secret in app (OK for you, not ideal for friends)."
fi

"$ROOT/scripts/apply-broker-credentials.sh"
"$ROOT/scripts/install-notchpro.sh"

echo ""
echo "All set. Friends only need: Settings → Integrations → Connect Schwab / Connect Webull"
