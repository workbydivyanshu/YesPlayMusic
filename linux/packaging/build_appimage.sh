#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-3.0.0}"
BUILD_DIR="${BUILD_DIR:-build/linux/x64/release/bundle}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"

APP_NAME="yesplaymusic"
APPIMAGE_TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
APPIMAGE_TOOL="${RUNNER_TEMP:-$HOME}/appimagetool-x86_64.AppImage"

mkdir -p "$OUTPUT_DIR"

if [ ! -x "$APPIMAGE_TOOL" ]; then
  echo "Downloading appimagetool..."
  curl -L -o "$APPIMAGE_TOOL" "$APPIMAGE_TOOL_URL"
  chmod +x "$APPIMAGE_TOOL"
fi

APPDIR="$(mktemp -d)/yesplaymusic.AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/lib/yesplaymusic"

# Binary / libs
if [ -x "$BUILD_DIR/yesplaymusic" ]; then
  cp -r "$BUILD_DIR"/* "$APPDIR/usr/lib/yesplaymusic/"
  ln -sf "../lib/yesplaymusic/yesplaymusic" "$APPDIR/usr/bin/yesplaymusic"
else
  echo "Binary not found at $BUILD_DIR/yesplaymusic" >&2
  exit 1
fi

# Desktop file and icon
cp "linux/packaging/yesplaymusic.desktop" "$APPDIR/$APP_NAME.desktop"
cp "linux/packaging/yesplaymusic.png" "$APPDIR/$APP_NAME.png"

# AppRun wrapper
cat > "$APPDIR/AppRun" <<EOF
#!/usr/bin/env bash
APPDIR="\$(dirname "\$(readlink -f "\$0")")"
export LD_LIBRARY_PATH="\$APPDIR/usr/lib/yesplaymusic:\$APPDIR/usr/lib/yesplaymusic/lib:\${LD_LIBRARY_PATH:-}"
exec "\$APPDIR/usr/lib/yesplaymusic/yesplaymusic" "\$@"
EOF
chmod +x "$APPDIR/AppRun"

# Ensure desktop Entry exec
sed -i 's|^Exec=.*|Exec=yesplaymusic|' "$APPDIR/$APP_NAME.desktop"

OUTPUT="YesPlayMusic-${VERSION}-x86_64.AppImage"
export ARCH=x86_64
"$APPIMAGE_TOOL" --appimage-extract-and-run "$APPDIR" "$OUTPUT_DIR/$OUTPUT"

echo "AppImage built: $OUTPUT_DIR/$OUTPUT"
