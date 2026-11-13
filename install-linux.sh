#!/usr/bin/env bash
# Diag-Tool installer for Linux (64-bit x86).
#
#   curl -fsSL https://raw.githubusercontent.com/RashestLynx/Diag-Tool/HEAD/install-linux.sh | bash
#
# Installs for your user only (no sudo):
#   app       -> ~/.local/share/diag-tool
#   command   -> ~/.local/bin/diag-tool
#   app menu  -> ~/.local/share/applications/diag-tool.desktop
#
# Run it again to update. To remove:  bash install-linux.sh --uninstall
set -euo pipefail

URL="https://github.com/RashestLynx/Diag-Tool/releases/download/latest/diag-tool-linux.tar.gz"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/diag-tool"
BIN_DIR="$HOME/.local/bin"
DESKTOP_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/applications/diag-tool.desktop"

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$APP_DIR" "$BIN_DIR/diag-tool" "$DESKTOP_FILE"
  echo "Diag-Tool removed."
  exit 0
fi

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
  echo "Sorry - this download is for 64-bit x86 Linux PCs (yours: $(uname -s) $(uname -m))." >&2
  echo "You can still use the command-line tool: see the README." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Diag-Tool..."
if command -v curl >/dev/null 2>&1; then
  curl -fL --progress-bar -o "$TMP/diag-tool.tar.gz" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q --show-progress -O "$TMP/diag-tool.tar.gz" "$URL"
else
  echo "Needs curl or wget. Install one (e.g. sudo apt install curl) and try again." >&2
  exit 1
fi

echo "Installing to $APP_DIR..."
mkdir -p "$TMP/app"
tar -xzf "$TMP/diag-tool.tar.gz" -C "$TMP/app"
chmod +x "$TMP/app/diag_tool"
rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
mv "$TMP/app" "$APP_DIR"

mkdir -p "$BIN_DIR"
ln -sf "$APP_DIR/diag_tool" "$BIN_DIR/diag-tool"

ICON="utilities-system-monitor"
[ -f "$APP_DIR/data/icon.png" ] && ICON="$APP_DIR/data/icon.png"
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Diag-Tool
Comment=Find out what's wrong with a device and how to fix it
Exec=$APP_DIR/diag_tool
Icon=$ICON
Terminal=false
Categories=Utility;System;
StartupWMClass=com.rashestlynx.diag_tool
EOF
command -v update-desktop-database >/dev/null 2>&1 \
  && update-desktop-database "$(dirname "$DESKTOP_FILE")" >/dev/null 2>&1 || true

if ! ldconfig -p 2>/dev/null | grep -q "libgtk-3.so.0"; then
  echo
  echo "Note: GTK 3 wasn't found. If the app won't open, install it:"
  echo "  Ubuntu/Debian/Mint: sudo apt install libgtk-3-0"
  echo "  Fedora:             sudo dnf install gtk3"
  echo "  Arch:               sudo pacman -S gtk3"
fi

echo
echo "Done! Open Diag-Tool from your app menu, or run:  diag-tool"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "(If 'diag-tool' isn't found, log out and back in, or run: $APP_DIR/diag_tool)" ;;
esac
