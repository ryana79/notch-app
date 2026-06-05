#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.broker-secrets.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

for var in SCHWAB_CLIENT_ID SCHWAB_CLIENT_SECRET NOTCHPRO_BROKER_PROXY_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "Set $var in .broker-secrets.env" >&2
    exit 1
  fi
done

if ! vercel whoami &>/dev/null; then
  echo "Vercel CLI is not authenticated." >&2
  echo "" >&2
  echo "Use your preferred browser (avoids Cursor opening the wrong Chrome profile):" >&2
  echo "  1. Open https://vercel.com/account/tokens in the browser you want" >&2
  echo "  2. Create a token, then run:" >&2
  echo "       export VERCEL_TOKEN='your-token-here'" >&2
  echo "  Or paste the token when prompted:" >&2
  echo "       vercel login --token" >&2
  echo "" >&2
  exit 1
fi

cd "$ROOT/broker-proxy"

set_env() {
  local name="$1"
  local value="$2"
  vercel env rm "$name" production --yes 2>/dev/null || true
  printf '%s' "$value" | vercel env add "$name" production
}

echo "Deploying NotchPro Schwab token proxy..."
vercel deploy --prod --yes >/tmp/notchpro-vercel-deploy.log 2>&1 || true
DEPLOY_URL="$(grep -Eo 'https://[a-zA-Z0-9.-]+\.vercel\.app' /tmp/notchpro-vercel-deploy.log | tail -1)"

echo "Setting production env vars on Vercel..."
set_env SCHWAB_CLIENT_ID "$SCHWAB_CLIENT_ID"
set_env SCHWAB_CLIENT_SECRET "$SCHWAB_CLIENT_SECRET"
set_env NOTCHPRO_BROKER_PROXY_KEY "$NOTCHPRO_BROKER_PROXY_KEY"

echo "Redeploying with env vars..."
vercel deploy --prod --yes 2>&1 | tee /tmp/notchpro-vercel-deploy.log
DEPLOY_URL="$(grep -Eo 'https://[a-zA-Z0-9.-]+\.vercel\.app' /tmp/notchpro-vercel-deploy.log | tail -1)"

if [[ -z "$DEPLOY_URL" ]]; then
  echo "Deploy failed — see /tmp/notchpro-vercel-deploy.log" >&2
  exit 1
fi

# Use the stable production alias (preview deployment URLs require Vercel login).
PROXY_URL="https://broker-proxy.vercel.app/api/schwab/token"

if grep -q '^SCHWAB_TOKEN_PROXY_URL=' "$ENV_FILE" 2>/dev/null; then
  sed -i '' "s|^SCHWAB_TOKEN_PROXY_URL=.*|SCHWAB_TOKEN_PROXY_URL=$PROXY_URL|" "$ENV_FILE"
else
  echo "SCHWAB_TOKEN_PROXY_URL=$PROXY_URL" >> "$ENV_FILE"
fi

echo ""
echo "Proxy live: $PROXY_URL"
echo "Saved SCHWAB_TOKEN_PROXY_URL to .broker-secrets.env"
