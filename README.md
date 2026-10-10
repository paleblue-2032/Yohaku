# shiori

栞付きの、シンプルで機能美に優れたメモ帳エディタ。

端末エディタ（nano / emacs など）のように「ちょっとメモしたい」ときに
ショートカットが効かない、という不便を解消するために作った小さな GUI エディタです。

![status](https://img.shields.io/badge/status-WIP-yellow)

## 特徴

- **標準ショートカットがそのまま効く** — Ctrl+C / V / X / Z / S などが普通に動く
- **栞（しおり）** — 名前どおり、本を読むように「場所」を覚える
  - 自動栞: ファイルごとに最後のカーソル位置を記憶し、次に開くとそこへ戻る
  - 手動栞: `Ctrl+B` で好きな行に ◆ を挟み、`Ctrl+J` の一覧からジャンプ
  - ファイル栞: `Ctrl+Shift+B` でよく開くファイルをお気に入り登録
- **タブ & セッション復元** — 終了時のタブを次回そのまま復元
- **自動保存ドラフト** — 無題ノートや未保存の変更を退避し、次回起動時に復元
- **Markdown プレビュー** — `Ctrl+P` でレンダリング表示
- **インクリメンタル検索** — `Ctrl+F`
- **日本語対応** — Noto Sans JP を同梱。fcitx5 などの IME からそのまま入力できる
- **単一バイナリ / クロスプラットフォーム** — Linux (Wayland/X11) / macOS / Windows

## インストール（NixOS / Nix flakes）

```nix
# flake.nix の inputs に追加
shiori = {
  url = "github:paleblue-2032/shiori";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```nix
# home-manager などで
home.packages = [ inputs.shiori.packages.${pkgs.system}.shiori ];
```

一時的に試すだけなら:

```sh
nix run github:paleblue-2032/shiori -- README.md
```

## 使い方

```
shiori                      # 空のノート（前回のセッションを復元）
shiori file.txt             # ファイルを開く
shiori a.md b.txt           # 複数ファイルをタブで開く
shiori -n                   # セッションを復元せず新規
```

すでに shiori が起動していれば、`shiori file` は既存ウィンドウのタブとして開きます
（Unix ドメインソケットによる単一インスタンス）。

## ショートカット

| キー | 動作 |
|---|---|
| `Ctrl+N` / `Ctrl+O` / `Ctrl+S` | 新規 / 開く / 保存 |
| `Ctrl+Shift+S` | 名前を付けて保存 |
| `Ctrl+W` / `Ctrl+Q` | タブを閉じる / 終了 |
| `Ctrl+Tab` (`Ctrl+PageUp/Down`) | タブ切替 |
| `Ctrl+F` | 検索（`Enter` 次、`Shift+Enter` 前、`Esc` 終了） |
| `Ctrl+B` | この行に栞を挟む/外す |
| `Ctrl+Shift+B` | このファイルをファイル栞に追加/削除 |
| `Ctrl+J` | 栞パネル |
| `Ctrl+P` | Markdown プレビュー切替 |
| `Ctrl+=` / `Ctrl+-` / `Ctrl+0` | 文字サイズ 拡大 / 縮小 / 等倍 |

## 設定・保存先

XDG 準拠。

- 設定: `$XDG_CONFIG_HOME/shiori/settings.json`
- セッション / 栞 / ドラフト: `$XDG_STATE_HOME/shiori/`

## ビルド

```sh
nix develop          # 開発環境
cargo run -- file.md # 実行
nix build            # ./result/bin/shiori
```

## ライセンス

MIT。同梱フォント Noto Sans JP は SIL Open Font License 1.1。
