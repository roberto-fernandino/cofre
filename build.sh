#!/usr/bin/env bash
# Compila o Cofre.app. Uso: ./build.sh            → build/Cofre.app
#                          ./build.sh --install  → também copia para ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product Cofre

APP=build/Cofre.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Cofre "$APP/Contents/MacOS/Cofre"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICONSET=build/AppIcon.iconset
if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
  rm -rf "$ICONSET"
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --options runtime "$APP"
echo "OK → $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Cofre.app"
  cp -R "$APP" "$HOME/Applications/Cofre.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Cofre.app"
  echo "Instalado → ~/Applications/Cofre.app"
fi
