#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Waallpaper"
ARCH="universal"
usage() {
    printf 'Usage: %s [--arch universal|host]\n' "$0"
    printf 'Creates a verified, ad hoc signed ZIP in build/releases/v<version>/.\n'
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            [[ $# -ge 2 && ( "$2" == universal || "$2" == host ) ]] || { usage >&2; exit 2; }
            ARCH="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$(uname -s)" == Darwin ]] || { printf 'macOS is required.\n' >&2; exit 1; }
plutil -lint "$PROJECT_DIR/scripts/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/scripts/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Expected a numeric major.minor.patch app version.\n' >&2; exit 1; }
RELEASE_ROOT="$PROJECT_DIR/build/releases"
RELEASE_DIR="$RELEASE_ROOT/v$VERSION"
[[ ! -e "$RELEASE_DIR" && ! -L "$RELEASE_DIR" ]] || { printf 'Release directory already exists: %s\n' "$RELEASE_DIR" >&2; exit 1; }
mkdir -p "$RELEASE_ROOT"
STAGING_DIR="$(mktemp -d "$RELEASE_ROOT/.waallpaper-release.XXXXXX")"
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

BUILD_ARGS=(--output "$STAGING_DIR/$APP_NAME.app")
if [[ "$ARCH" == universal ]]; then
    BUILD_ARGS+=(--universal)
    EXPECTED_ARCHS="arm64 x86_64"
else
    ARCH="$(uname -m)"
    EXPECTED_ARCHS="$ARCH"
fi
"$PROJECT_DIR/scripts/build-app.sh" "${BUILD_ARGS[@]}"
APP="$STAGING_DIR/$APP_NAME.app"
ARTIFACTS="$STAGING_DIR/artifacts"
mkdir "$ARTIFACTS"
ARCHIVE="$APP_NAME-$VERSION-macOS-$ARCH.zip"
ditto --norsrc -c -k --keepParent "$APP" "$ARTIFACTS/$ARCHIVE"
python3 - "$ARTIFACTS/$ARCHIVE" <<'PY'
import pathlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as zipped:
    for name in zipped.namelist():
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'Waallpaper.app':
            raise SystemExit(f'Unexpected archive member: {name}')
PY
mkdir "$STAGING_DIR/verification"
ditto -x -k "$ARTIFACTS/$ARCHIVE" "$STAGING_DIR/verification"
EXTRACTED_APP="$STAGING_DIR/verification/$APP_NAME.app"

# Compare every archived file and executable bit, and reject unexpected paths.
python3 - "$APP" "$EXTRACTED_APP" "$EXPECTED_ARCHS" <<'PY'
import hashlib, pathlib, plistlib, stat, subprocess, sys
source, extracted, expected_archs = sys.argv[1:]
def inventory(root):
    result = {}
    for path in pathlib.Path(root).rglob('*'):
        if path.is_symlink():
            raise SystemExit(f'Unexpected symbolic link in app: {path.relative_to(root)}')
        if path.is_file():
            result[str(path.relative_to(root))] = (
                hashlib.sha256(path.read_bytes()).hexdigest(),
                stat.S_IMODE(path.stat().st_mode) & 0o111,
            )
    return result
if inventory(source) != inventory(extracted):
    raise SystemExit('Archive round-trip changed app contents or executable permissions.')
app = pathlib.Path(extracted)
with (app / 'Contents/Info.plist').open('rb') as file:
    plist = plistlib.load(file)
if plist.get('CFBundleExecutable') != 'Waallpaper' or plist.get('CFBundlePackageType') != 'APPL':
    raise SystemExit('Invalid app executable or package type.')
for language in ('en', 'ko'):
    strings = app / f'Contents/Resources/Waallpaper_WaallpaperCore.bundle/Contents/Resources/{language}.lproj/Localizable.strings'
    if not strings.is_file() or not strings.stat().st_size:
        raise SystemExit(f'Missing localization: {language}')
    subprocess.run(['plutil', '-lint', str(strings)], check=True)
executable = str(app / 'Contents/MacOS/Waallpaper')
actual = subprocess.check_output(['lipo', '-archs', executable], text=True).split()
if set(actual) != set(expected_archs.split()):
    raise SystemExit(f'Architecture mismatch after archive: {actual}')
subprocess.run(['plutil', '-lint', str(app / 'Contents/Info.plist')], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], check=True)
PY

cat > "$ARTIFACTS/RELEASE-INFO.txt" <<EOF
Application: $APP_NAME
Version: $VERSION
Architectures: $EXPECTED_ARCHS
Signing: ad hoc (no Developer ID certificate)
Notarization: not performed
Archive verification: extracted contents, executable permissions, localizations, architectures, and strict code signature passed
EOF
(cd "$ARTIFACTS" && shasum -a 256 "$ARCHIVE" RELEASE-INFO.txt > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
# RENAME_EXCL atomically publishes the complete directory without overwriting
# another run or an existing release that appeared while this run was building.
python3 - "$ARTIFACTS" "$RELEASE_DIR" <<'PY'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
rename = libc.renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
if rename(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 0x00000004):  # RENAME_EXCL
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error), sys.argv[2])
PY
printf 'Release artifacts: %s\n' "$RELEASE_DIR"
