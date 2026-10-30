#!/bin/zsh
# Builds DeskNote.app into ~/Applications and (re)starts it.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/DeskNote.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/DeskNote"
rm -rf "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources"
cp -R preview.html katex "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>DeskNote</string>
  <key>CFBundleIdentifier</key><string>com.haydenfletcher.desknote</string>
  <key>CFBundleExecutable</key><string>DeskNote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - "$APP"
pkill -x DeskNote || true
open "$APP"
