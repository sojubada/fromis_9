#!/bin/bash
# tvOS 앱(IPA) 빌드. macOS + Xcode 필요. 서명하지 않은 IPA 를 만들어 TrollStore 로 설치한다.
set -euo pipefail
cd "$(dirname "$0")/.."
VER=$(tr -d '[:space:]' < VERSION)
SDK=$(xcrun --sdk appletvos --show-sdk-path)
OUT=build
APP="$OUT/Payload/HangulByeolbam.app"
rm -rf "$OUT"; mkdir -p "$APP/www"
echo "SDK: $SDK"; xcrun --sdk appletvos swiftc --version
xcrun --sdk appletvos swiftc -swift-version 5 -parse-as-library -O \
  -target arm64-apple-tvos15.0 -sdk "$SDK" \
  tv/Sources/*.swift -o "$APP/HangulByeolbam"
cp index.html "$APP/www/"
cp -r img "$APP/www/img"
cp tv/www/setup.html "$APP/www/"
sed "s/__VERSION__/$VER/g" tv/Info.plist > "$APP/Info.plist"
if command -v ldid >/dev/null 2>&1; then ldid -S "$APP/HangulByeolbam" || true; fi
(cd "$OUT" && zip -qry "HangulByeolbam-v$VER.ipa" Payload)
ls -la "$OUT"
