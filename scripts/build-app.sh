#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Waallpaper"
APP_DIR="$PROJECT_DIR/build/$APP_NAME.app"
BUILD_ARGS=(-c release)
EXPECTED_ARCHS="$(uname -m)"

usage() {
    printf 'Usage: %s [--universal] [--output PATH.app]\n' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --universal)
            BUILD_ARGS+=(--arch arm64 --arch x86_64)
            EXPECTED_ARCHS="arm64 x86_64"
            shift
            ;;
        --output)
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
            APP_DIR="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$(uname -s)" == Darwin ]] || { printf 'macOS is required.\n' >&2; exit 1; }
APP_DIR="$(python3 - "$APP_DIR" <<'PY'
import os, sys
path = os.path.abspath(sys.argv[1])
if not path.endswith('.app') or os.path.islink(path):
    raise SystemExit('Output must be an .app path, not a symbolic link.')
print(path)
PY
)"
mkdir -p "$(dirname "$APP_DIR")"
STAGING_DIR="$(mktemp -d "$(dirname "$APP_DIR")/.waallpaper-build.XXXXXX")"
cleanup() {
    local status=$?
    python3 - "$STAGING_DIR" <<'PY' || true
import shutil, sys
shutil.rmtree(sys.argv[1])
PY
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

STAGED_APP="$STAGING_DIR/$APP_NAME.app"
swift build --package-path "$PROJECT_DIR" "${BUILD_ARGS[@]}" --product "$APP_NAME"
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$STAGED_APP/Contents/MacOS/$APP_NAME"
# The localization accessor explicitly finds this resource bundle in the app.
ditto --norsrc "$BIN_DIR/${APP_NAME}_${APP_NAME}Core.bundle" \
    "$STAGED_APP/Contents/Resources/${APP_NAME}_${APP_NAME}Core.bundle"
cp "$PROJECT_DIR/scripts/Info.plist" "$STAGED_APP/Contents/Info.plist"
swift "$PROJECT_DIR/scripts/make-icon.swift" "$STAGING_DIR/AppIcon.iconset"
iconutil -c icns "$STAGING_DIR/AppIcon.iconset" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"

plutil -lint "$STAGED_APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$STAGED_APP/Contents/Info.plist")" == "$APP_NAME" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$STAGED_APP/Contents/Info.plist")" == APPL ]]
[[ -x "$STAGED_APP/Contents/MacOS/$APP_NAME" && -s "$STAGED_APP/Contents/Resources/AppIcon.icns" ]]
for language in en ko; do
    strings="$STAGED_APP/Contents/Resources/${APP_NAME}_${APP_NAME}Core.bundle/Contents/Resources/$language.lproj/Localizable.strings"
    [[ -s "$strings" ]]
    plutil -lint "$strings"
done
ACTUAL_ARCHS="$(lipo -archs "$STAGED_APP/Contents/MacOS/$APP_NAME")"
python3 - "$EXPECTED_ARCHS" "$ACTUAL_ARCHS" <<'PY'
import sys
if set(sys.argv[1].split()) != set(sys.argv[2].split()):
    raise SystemExit(f'Architecture mismatch: expected {sys.argv[1]}, found {sys.argv[2]}')
PY
codesign --force --sign - --timestamp=none "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

# Both paths are on the same volume. An existing matching app is swapped in one
# atomic operation; its old contents then remain inside our staging directory.
python3 - "$STAGED_APP" "$APP_DIR" <<'PY'
import ctypes, os, plistlib, sys
source, destination = sys.argv[1:]
libc = ctypes.CDLL(None, use_errno=True)
rename = libc.renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
flags = 0x00000004  # RENAME_EXCL
if os.path.lexists(destination):
    if os.path.islink(destination) or not os.path.isdir(destination):
        raise SystemExit('Refusing to replace an output that is not an app directory.')
    def identifier(path):
        with open(os.path.join(path, 'Contents', 'Info.plist'), 'rb') as file:
            return plistlib.load(file).get('CFBundleIdentifier')
    if not identifier(source) or identifier(source) != identifier(destination):
        raise SystemExit('Refusing to replace an app with a different bundle identifier.')
    flags = 0x00000002  # RENAME_SWAP
if rename(os.fsencode(source), os.fsencode(destination), flags):
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error), destination)
PY
printf 'Built (%s; ad hoc signed): %s\n' "$ACTUAL_ARCHS" "$APP_DIR"
