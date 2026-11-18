#!/usr/bin/env bash
# Packs build/Cofre.app into build/Cofre.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE=build/dmg
rm -rf "$STAGE" build/Cofre.dmg
mkdir -p "$STAGE"
cp -R build/Cofre.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Cofre" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/Cofre.dmg >/dev/null
rm -rf "$STAGE"
shasum -a 256 build/Cofre.dmg | tee build/Cofre.dmg.sha256
