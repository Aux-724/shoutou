#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release
app="$HOME/Applications/Shoutou.app"

if pgrep -x Shoutou >/dev/null; then
  pkill -x Shoutou || true
  sleep 0.4
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/.build/release/Shoutou" "$app/Contents/MacOS/Shoutou"
cp "$root/Info.plist" "$app/Contents/Info.plist"
chmod +x "$app/Contents/MacOS/Shoutou"
codesign --force --sign - "$app"

echo "已安装到 $app"
echo "看菜单栏右侧的旗子。第一次打开会弹出面板。"
open "$app"
