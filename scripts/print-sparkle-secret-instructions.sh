#!/bin/bash
# Prints steps to add the Sparkle private key to GitHub Actions.
set -euo pipefail
KEY_FILE="$(cd "$(dirname "$0")/.." && pwd)/Configuration/sparkle/ed_private_key.txt"
if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing $KEY_FILE — run generate_keys first (see Configuration/sparkle/SETUP.md)" >&2
  exit 1
fi
echo "Add GitHub repository secret:"
echo "  Name:  PRIVATE_SPARKLE_KEY"
echo "  Value: (paste the single line below)"
echo ""
cat "$KEY_FILE"
echo ""
echo "Repo: Settings → Secrets and variables → Actions → New repository secret"
