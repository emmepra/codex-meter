#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SPARKLE_DIR="$PWD/.build/sparkle-2.10.0"
if [[ -f "$SPARKLE_DIR/.verified" && -d "$SPARKLE_DIR/Sparkle.framework" ]]; then exit 0; fi
mkdir -p .build
STAGING=$(mktemp -d "$PWD/.build/sparkle-download.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz -o "$STAGING/archive.tar.xz"
EXPECTED=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
ACTUAL=$(shasum -a 256 "$STAGING/archive.tar.xz" | cut -d ' ' -f 1)
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo 'Sparkle checksum mismatch' >&2; exit 1; }
mkdir "$STAGING/unpacked"
tar -xf "$STAGING/archive.tar.xz" -C "$STAGING/unpacked"
codesign --verify --deep --strict "$STAGING/unpacked/Sparkle.framework"
touch "$STAGING/unpacked/.verified"
# Never replace an unexpected pre-existing dependency directory.
[[ ! -e "$SPARKLE_DIR" ]] || { echo 'Remove the incomplete Sparkle cache before retrying.' >&2; exit 1; }
mv "$STAGING/unpacked" "$SPARKLE_DIR"
