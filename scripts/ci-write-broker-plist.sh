#!/bin/bash
# Writes BrokerCredentials.plist for CI from environment variables (GitHub Actions secrets).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/NotchPro/Resources/BrokerCredentials.plist"
EXAMPLE="$ROOT/NotchPro/Resources/BrokerCredentials.example.plist"

cp "$EXAMPLE" "$PLIST"
export PLIST_PATH="$PLIST"

python3 <<'PY'
import os
import plistlib
from pathlib import Path

plist_path = Path(os.environ["PLIST_PATH"])
with plist_path.open("rb") as f:
    data = plistlib.load(f)

data["SchwabClientID"] = os.environ.get("SCHWAB_CLIENT_ID", "").strip()
data["SchwabClientSecret"] = os.environ.get("SCHWAB_CLIENT_SECRET", "").strip()
data["SchwabTokenProxyURL"] = os.environ.get("SCHWAB_TOKEN_PROXY_URL", "").strip()
data["BrokerProxyAPIKey"] = os.environ.get("NOTCHPRO_BROKER_PROXY_KEY", "").strip()
data["WebullAppKey"] = os.environ.get("WEBULL_APP_KEY", "").strip()
data["WebullAppSecret"] = os.environ.get("WEBULL_APP_SECRET", "").strip()

with plist_path.open("wb") as f:
    plistlib.dump(data, f)

schwab = bool(data["SchwabClientID"]) and (
    bool(data["SchwabClientSecret"]) or bool(data["SchwabTokenProxyURL"])
)
print(f"BrokerCredentials.plist written (Schwab: {'yes' if schwab else 'no'})")
PY
