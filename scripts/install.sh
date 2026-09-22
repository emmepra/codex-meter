#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALL_DIR="$HOME/Applications"

usage() {
  printf '%s\n' 'Usage: ./scripts/install.sh [--destination DIRECTORY]' \
    'Build and install Codex Meter. Default destination: ~/Applications.' \
    'Quit Codex Meter from its … > Esci menu before installing or updating.'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination)
      if [[ $# -lt 2 || -z "$2" ]]; then usage >&2; exit 2; fi
      INSTALL_DIR="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  printf '%s\n' 'This installer requires an Apple Silicon Mac.' >&2
  exit 1
fi

require_stopped() {
  local process_status=0
  /usr/bin/pgrep -x CodexMeter >/dev/null || process_status=$?
  case "$process_status" in
    0)
      printf '%s\n' 'Codex Meter is running. Choose … > Esci (Quit) in its menu, then retry.' >&2
      exit 1
      ;;
    1) ;;
    *) printf '%s\n' 'Could not check whether Codex Meter is running; installation stopped.' >&2; exit 1 ;;
  esac
}

require_stopped
"$PROJECT_DIR/scripts/build.sh"
mkdir -p "$INSTALL_DIR"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd -P)"
if [[ "$INSTALL_DIR" == "$PROJECT_DIR/.build" || "$INSTALL_DIR" == "$PROJECT_DIR/.build/"* ]]; then
  printf '%s\n' 'Choose a destination outside .build; that directory already contains the build output.' >&2
  exit 1
fi
INSTALLED_APP="$INSTALL_DIR/Codex Meter.app"

# Replace only this app, never an unrelated folder or a symbolic link.
if [[ -L "$INSTALLED_APP" ]]; then
  printf '%s\n' 'The destination app is a symbolic link. Choose another destination.' >&2
  exit 1
fi
if [[ -e "$INSTALLED_APP" ]]; then
  existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$existing_id" != it.emmepra.codex-meter ]]; then
    printf '%s\n' 'The destination already contains an unrelated item named Codex Meter.app.' >&2
    exit 1
  fi
fi

STAGING_DIR=$(mktemp -d "$INSTALL_DIR/.codex-meter-install.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto --norsrc --noextattr "$PROJECT_DIR/.build/Codex Meter.app" "$STAGING_DIR/Codex Meter.app"
/usr/bin/codesign --verify --strict "$STAGING_DIR/Codex Meter.app"
require_stopped
if [[ -e "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$STAGING_DIR/previous.app"
fi
if ! mv "$STAGING_DIR/Codex Meter.app" "$INSTALLED_APP" || ! /usr/bin/codesign --verify --strict "$INSTALLED_APP"; then
  printf '%s\n' 'Installation failed; restoring the previous app when available.' >&2
  if [[ -e "$INSTALLED_APP" ]] && ! mv "$INSTALLED_APP" "$STAGING_DIR/failed.app"; then
    trap - EXIT
    printf 'Rollback failed. Recovery files retained at: %s\n' "$STAGING_DIR" >&2
    exit 1
  fi
  if [[ -d "$STAGING_DIR/previous.app" ]] && ! mv "$STAGING_DIR/previous.app" "$INSTALLED_APP"; then
    trap - EXIT
    printf 'Rollback failed. Previous app retained at: %s/previous.app\n' "$STAGING_DIR" >&2
  fi
  exit 1
fi
printf 'Installed: %s\n' "$INSTALLED_APP"
