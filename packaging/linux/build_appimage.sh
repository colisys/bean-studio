#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds a self-contained AppDir and packages it as an AppImage.
# The host system still provides GTK 3 / GLib, which every mainstream desktop has.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT_DIR/build/linux/x64/release/bundle}"
APPIMAGETOOL="${APPIMAGETOOL:-appimagetool}"
APP_VERSION="${APP_VERSION:-1.0.0}"
OUTPUT="${1:-$ROOT_DIR/dist/BeadStudio-linux-x86_64.AppImage}"

if [[ ! -x "$BUNDLE_DIR/bead_studio" ]]; then
  echo "Flutter Linux release bundle not found at $BUNDLE_DIR" >&2
  exit 1
fi
if ! command -v "$APPIMAGETOOL" >/dev/null 2>&1 && [[ ! -x "$APPIMAGETOOL" ]]; then
  echo "appimagetool not found. Set APPIMAGETOOL=/path/to/appimagetool." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
APPDIR="$WORK_DIR/AppDir"

mkdir -p \
  "$APPDIR/usr/bin" \
  "$APPDIR/usr/lib/bead_studio" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps"

cp -a "$BUNDLE_DIR/." "$APPDIR/usr/lib/bead_studio/"
find "$APPDIR/usr/lib/bead_studio" -type f -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true

ln -s ../lib/bead_studio/bead_studio "$APPDIR/usr/bin/bead_studio"
cp "$ROOT_DIR/packaging/linux/AppRun" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
sed "s/@APP_VERSION@/${APP_VERSION}/g" \
  "$ROOT_DIR/packaging/linux/bead_studio.desktop" > "$APPDIR/bead_studio.desktop"
cp "$APPDIR/bead_studio.desktop" "$APPDIR/usr/share/applications/bead_studio.desktop"

cp "$ROOT_DIR/assets/icon/app_icon.png" "$APPDIR/bead_studio.png"
cp "$ROOT_DIR/assets/icon/app_icon.png" "$APPDIR/.DirIcon"
cp "$ROOT_DIR/assets/icon/app_icon.png" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps/bead_studio.png"

mkdir -p "$(dirname "$OUTPUT")"
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 \
  "$APPIMAGETOOL" --no-appstream "$APPDIR" "$OUTPUT"

echo "AppImage written to $OUTPUT"
