#!/bin/sh
# Mac 版（Apple シリコン + Intel のユニバーサル）をビルドする。
# （Xcode 27 の lipo の不具合よけは macos/Runner.xcodeproj のビルドスクリプトで tool/lipo-shim を使って行う）
set -e
cd "$(dirname "$0")/.."
flutter build macos --release "$@"
APP="build/macos/Build/Products/Release/PONG!.app"
echo
echo "できあがり: $APP"
echo "アーキテクチャ: $(lipo -archs "$APP/Contents/MacOS/PONG!")"
