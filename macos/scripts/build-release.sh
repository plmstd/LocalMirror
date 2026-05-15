#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:a:h:h}"
ARCHIVE_PATH="${PROJECT_ROOT}/build/LocalMirror.xcarchive"
EXPORT_PATH="${PROJECT_ROOT}/build/export"

mkdir -p "${PROJECT_ROOT}/build"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"

xcodebuild \
  -project "${PROJECT_ROOT}/LocalMirror.xcodeproj" \
  -scheme "LocalMirror" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  archive

echo "Archive created at ${ARCHIVE_PATH}"
echo "Export the app with your preferred signing/export options, then notarize it with scripts/notarize-app.sh."
