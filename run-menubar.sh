#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

./stop-menubar.sh || true

TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist build GithubMonitor --configuration Debug

LATEST_APP_PATH=""
LATEST_MTIME=0

while IFS= read -r app_path; do
  app_mtime="$(stat -f "%m" "$app_path")"
  if [[ "$app_mtime" -gt "$LATEST_MTIME" ]]; then
    LATEST_MTIME="$app_mtime"
    LATEST_APP_PATH="$app_path"
  fi
done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -path "*/Build/Products/Debug/GithubMonitor.app")

if [[ -z "$LATEST_APP_PATH" ]]; then
  echo "Could not locate GithubMonitor.app in DerivedData" >&2
  exit 1
fi

open "$LATEST_APP_PATH"
