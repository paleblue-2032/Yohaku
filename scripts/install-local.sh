#!/usr/bin/env bash
#
# 展開済みの Yohaku をホームディレクトリへインストールする（tarball に同梱される）
#
#   ./install.sh
#
# 環境変数:
#   YOHAKU_PREFIX … インストール先（既定: ~/.local）
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${YOHAKU_PREFIX:-$HOME/.local}"

bin_dir="$PREFIX/bin"
opt_dir="$PREFIX/opt/yohaku"
app_dir="$PREFIX/share/applications"
icon_dir="$PREFIX/share/icons"

mkdir -p "$bin_dir" "$opt_dir" "$app_dir" "$icon_dir"

[ -d "$here/bin" ] && cp -a "$here/bin/." "$opt_dir/bin/"
[ -d "$here/share" ] && cp -a "$here/share/." "$opt_dir/share/"
[ -f "$here/README.txt" ] && cp -a "$here/README.txt" "$opt_dir/"
ln -sf "$opt_dir/bin/yohaku" "$bin_dir/yohaku"

if [ -f "$here/share/applications/yohaku.desktop" ]; then
  install -m644 "$here/share/applications/yohaku.desktop" "$app_dir/yohaku.desktop"
fi
if [ -d "$here/share/icons/hicolor" ]; then
  cp -a "$here/share/icons/hicolor/." "$icon_dir/hicolor/"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$app_dir" >/dev/null 2>&1 || true
fi

echo "インストールしました: $bin_dir/yohaku"
