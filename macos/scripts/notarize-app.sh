#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app-path> <notary-profile>"
  exit 1
fi

APP_PATH="$1"
PROFILE_NAME="$2"

xcrun notarytool submit "${APP_PATH}" \
  --keychain-profile "${PROFILE_NAME}" \
  --wait

xcrun stapler staple "${APP_PATH}"
echo "Notarization complete for ${APP_PATH}"
