# shiori

栞付きの、シンプルで機能美に優れたメモ帳エディタ。**Qt 6 / QML** 実装。

端末エディタ（nano / emacs など）のように「ちょっとメモしたい」ときに
ショートカットが効かない、という不便を解消するために作った小さな GUI エディタです。

## 特徴

- **標準ショートカットがそのまま効く** — Ctrl+C / V / X / Z / S など
- **タブ** — 複数ファイルをタブで。単独起動は新しいタブで開始
- **栞** — 自動（最後のカーソル位置を記憶して次回そこへ戻る）、手動（`Ctrl+B`）、ファイル栞（`Ctrl+Shift+B`）
- **セッション復元 & 自動保存ドラフト** — 終了時のタブと未保存内容を復元
- **日本語入力** — fcitx5 などの IME からそのまま入力できる
- **多言語 UI** — 英語 / 日本語（既定は英語、設定メニューから切替）
- **テーマ & アクセントカラー** — ダーク / ライト、5 色のアクセント
- **行番号 / 折り返し** — 表示メニューから切替
- **メニューのキーボード操作** — メニューを開いて ↑↓ で移動、Enter で決定
- **単一インスタンス** — `shiori file` は起動中のウィンドウにタブ追加
- **クロスプラットフォーム** — Linux (Wayland/X11) / macOS / Windows

未実装（予定）: インクリメンタル検索、Markdown プレビュー。

> このリポジトリは以前の Rust + egui 実装を Qt6/QML に置き換えたものです
> （旧実装は git 履歴に残っています）。

## 必要なもの

- Qt 6.5 以上（`qtbase` / `qtdeclarative`）
- CMake 3.21 以上、Ninja、C++17 コンパイラ

## インストール

### 1. 試すだけ（インストールしない）

```sh
nix run github:paleblue-2032/shiori
```

### 2. ユーザー環境に直接入れる（命令的）

```sh
nix profile install github:paleblue-2032/shiori
# アンインストール: nix profile remove shiori
```

### 3. 宣言的に入れる（NixOS / home-manager・推奨）

`flake.nix` の inputs に追加:

```nix
shiori = {
  url = "github:paleblue-2032/shiori";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

`home-manager` のパッケージ一覧に追記:

```nix
home.packages = [
  inputs.shiori.packages.${pkgs.system}.shiori
];
```

あとは反映:

```sh
sudo nixos-rebuild switch --flake <your-flake>#<host>
```

### ランチャ / 検索への表示

パッケージに `.desktop` とアイコンを同梱しています:

- `share/applications/shiori.desktop`
- `share/icons/hicolor/scalable/apps/shiori.svg`

プロファイルの `share` は `XDG_DATA_DIRS` に含まれるため、2 / 3 の方法で
入れると GNOME のアクティビティ検索や Noctalia などのランチャに **shiori** が
アプリとして表示されます。

### Nix 以外

```sh
cmake -B build -G Ninja
cmake --build build
./build/shiori
```

## ショートカット

| キー | 動作 |
|---|---|
| `Ctrl+N` / `Ctrl+O` | 新規 / 開く |
| `Ctrl+S` | 保存 |
| `Ctrl+W` / `Ctrl+Q` | タブを閉じる / 終了 |
| `Alt` → `←→` → `Enter` | メニュー操作（↑↓ でも移動可） |

## ライセンス

MIT
