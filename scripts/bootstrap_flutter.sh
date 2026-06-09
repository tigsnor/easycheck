#!/usr/bin/env bash
set -euo pipefail

# Installs a local Flutter SDK for this repository when the host machine does
# not already provide `flutter` on PATH.
#
# Usage:
#   scripts/bootstrap_flutter.sh
#   FLUTTER_HOME=/custom/path/flutter scripts/bootstrap_flutter.sh
#
# The default install location is .tool/flutter, which is intentionally ignored
# by git so the SDK is never committed to the repository.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_HOME="${FLUTTER_HOME:-$ROOT_DIR/.tool/flutter}"
RELEASES_JSON_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
VERSION_FILE="$ROOT_DIR/.fvmrc"
REQUESTED_VERSION="${FLUTTER_VERSION:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["flutter"])' "$VERSION_FILE")}"
ARCHIVE_BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases"

flutter_matches_requested_version() {
  local flutter_binary="$1"
  local version_output
  version_output="$("$flutter_binary" --version 2>/dev/null)"
  grep -q "Flutter $REQUESTED_VERSION " <<<"$version_output"
}

if command -v flutter >/dev/null 2>&1 && flutter_matches_requested_version "$(command -v flutter)"; then
  echo "Flutter $REQUESTED_VERSION is already available: $(command -v flutter)"
  flutter --version
  exit 0
fi

if [ -x "$FLUTTER_HOME/bin/flutter" ] && flutter_matches_requested_version "$FLUTTER_HOME/bin/flutter"; then
  echo "Using existing local Flutter $REQUESTED_VERSION SDK: $FLUTTER_HOME"
  "$FLUTTER_HOME/bin/flutter" --version
  exit 0
fi

if [ -d "$FLUTTER_HOME" ]; then
  echo "Removing Flutter SDK that does not match $REQUESTED_VERSION: $FLUTTER_HOME"
  rm -rf "$FLUTTER_HOME"
fi

mkdir -p "$(dirname "$FLUTTER_HOME")"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Flutter was not found on PATH. Installing Flutter $REQUESTED_VERSION to $FLUTTER_HOME"

if curl -L --fail --retry 3 --connect-timeout 20 "$RELEASES_JSON_URL" -o "$TMP_DIR/releases_linux.json"; then
  ARCHIVE_PATH="$(python3 - "$TMP_DIR/releases_linux.json" "$REQUESTED_VERSION" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as fh:
    data = json.load(fh)

requested_version = sys.argv[2]
release = next(
    item for item in data['releases']
    if item.get('version') == requested_version and item.get('channel') == 'stable'
)
print(release['archive'])
PY
)"
  ARCHIVE_URL="$ARCHIVE_BASE_URL/$ARCHIVE_PATH"
  echo "Downloading Flutter stable archive: $ARCHIVE_URL"
  curl -L --fail --retry 3 --connect-timeout 20 "$ARCHIVE_URL" -o "$TMP_DIR/flutter.tar.xz"
  tar -xf "$TMP_DIR/flutter.tar.xz" -C "$(dirname "$FLUTTER_HOME")"
elif command -v git >/dev/null 2>&1; then
  echo "Release archive metadata was unavailable. Falling back to git clone of Flutter stable."
  git clone --depth 1 -b "$REQUESTED_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
else
  echo "Neither Flutter archive download nor git fallback is available." >&2
  exit 1
fi

git config --global --add safe.directory "$FLUTTER_HOME" || true
"$FLUTTER_HOME/bin/flutter" config --no-analytics
"$FLUTTER_HOME/bin/flutter" --version

echo
printf 'Flutter is ready. Add this to your shell PATH for this session:\n  export PATH="%s/bin:$PATH"\n' "$FLUTTER_HOME"
