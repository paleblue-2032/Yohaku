#!/usr/bin/env bash
#
# Yohaku インストーラ（Linux / macOS）
#
#   curl -fsSL https://raw.githubusercontent.com/paleblue-2032/yohaku/main/scripts/install.sh | bash
#
# 環境変数:
#   YOHAKU_VERSION … 入れるバージョン（既定: latest）
#   YOHAKU_PREFIX  … Linux でのインストール先（既定: ~/.local）
set -euo pipefail

REPO="paleblue-2032/yohaku"
VERSION="${YOHAKU_VERSION:-latest}"
PREFIX="${YOHAKU_PREFIX:-$HOME/.local}"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

os="$(uname -s)"
arch="$(uname -m)"

case "$os-$arch" in
  Linux-x86_64)  asset="yohaku-linux-x86_64.tar.gz" ;;
  Darwin-arm64)  asset="yohaku-macos-arm64.zip" ;;
  Darwin-x86_64) asset="yohaku-macos-x86_64.zip" ;;
  *)
    say "この環境 ($os $arch) 用のビルドはまだありません。"
    say "Nix が使えるなら: nix run github:$REPO"
    exit 1
    ;;
esac

if [ "$VERSION" = "latest" ]; then
  url="https://github.com/$REPO/releases/latest/download/$asset"
else
  url="https://github.com/$REPO/releases/download/v${VERSION#v}/$asset"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Yohaku をダウンロードします: $asset"
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 -o "$tmp/$asset" "$url"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$tmp/$asset" "$url"
else
  die "curl か wget が必要です"
fi

if [ "$os" = "Darwin" ]; then
  ditto -x -k "$tmp/$asset" "$tmp/out"
  app="$(find "$tmp/out" -maxdepth 2 -name '*.app' | head -1)"
  [ -n "$app" ] || die ".app が見つかりませんでした"

  target="/Applications"
  [ -w "$target" ] || target="$HOME/Applications"
  mkdir -p "$target"
  rm -rf "$target/$(basename "$app")"
  cp -R "$app" "$target/"

  # Gatekeeper の「開発元を確認できません」を避ける（自己署名なしビルドのため）
  xattr -dr com.apple.quarantine "$target/$(basename "$app")" 2>/dev/null || true

  # ターミナルからも使えるようにコマンドを作る
  sudo ln -sf "$target/$(basename "$app")/Contents/MacOS/yohaku" /usr/local/bin/yohaku 2>/dev/null \
    || say "ヒント: ターミナルから使うには /Applications/$(basename "$app")/Contents/MacOS/yohaku を PATH に置いてください"

  say "インストールしました: $target/$(basename "$app")"
  say "Launchpad か Finder の「アプリケーション」から起動できます。"
else
  mkdir -p "$tmp/out"
  tar -xzf "$tmp/$asset" -C "$tmp/out"

  if [ -f "$tmp/out/install.sh" ]; then
    YOHAKU_PREFIX="$PREFIX" bash "$tmp/out/install.sh"
  else
    mkdir -p "$PREFIX/opt/yohaku" "$PREFIX/bin"
    cp -a "$tmp/out/." "$PREFIX/opt/yohaku/"
    ln -sf "$PREFIX/opt/yohaku/bin/yohaku" "$PREFIX/bin/yohaku"
    say "インストールしました: $PREFIX/bin/yohaku"
  fi

  case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) say "ヒント: PATH に $PREFIX/bin を追加すると 'yohaku' で起動できます" ;;
  esac

  if [ -f "$tmp/out/README.txt" ]; then
    say "（Qt6 が必要です。詳しくは $PREFIX/opt/yohaku/README.txt を参照）"
  fi
fi
