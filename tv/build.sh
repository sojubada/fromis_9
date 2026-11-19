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
cp -r fonts "$APP/www/fonts"
cp -r img "$APP/www/img"
cp tv/www/setup.html "$APP/www/"
sed "s/__VERSION__/$VER/g" tv/Info.plist > "$APP/Info.plist"
# 앱 아이콘·탑 셸프 (실패해도 빌드는 계속)
if xcrun actool tv/icon/Assets.xcassets --compile "$APP" --platform appletvos \
     --minimum-deployment-target 15.0 --target-device tv \
     --app-icon "App Icon & Top Shelf Image" --output-partial-info-plist "$OUT/icon.plist" \
     --errors --warnings --notices; then
  /usr/libexec/PlistBuddy -c "Merge $OUT/icon.plist" "$APP/Info.plist" && echo "ICON: OK"
  ls -la "$APP" | grep -i -E "car|png" || true
else
  echo "ICON: actool failed"
fi
if command -v ldid >/dev/null 2>&1; then ldid -S "$APP/HangulByeolbam" || true; fi
(cd "$OUT" && zip -qry "HangulByeolbam-v$VER.ipa" Payload)
ls -la "$OUT"
