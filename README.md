# shiori

栞付きの、シンプルで機能美に優れたメモ帳エディタ。**Qt 6 / QML** 実装。

端末エディタ（nano / emacs など）のように「ちょっとメモしたい」ときに
ショートカットが効かない、という不便を解消するために作った小さな GUI エディタです。

## 特徴

- **標準ショートカットがそのまま効く** — Ctrl+C / V / X / Z / S など
- **タブ** — 複数ファイルをタブで。`Ctrl+T` で新しいタブ、`Ctrl+Tab` で切替。**起動時は常に新しいタブ**で開始（前回のタブは復元しない）
- **栞** — 自動（最後のカーソル位置を記憶して次回そこへ戻る）、手動（`Ctrl+B`）、ファイル栞（`Ctrl+Shift+B`）
- **日本語入力** — fcitx5 などの IME からそのまま入力できる
- **多言語 UI** — 英語 / 日本語（既定は英語、設定メニューから切替）
- **テーマ & アクセントカラー** — ダーク / ライト、5 色のアクセント
- **透過** — 設定メニューから なし / 弱 / 中 / 強。※コンポジタ側にブラー（すりガラス）が無い環境では、強い透過は文字が読みづらくなります（niri 25.08 は blur 非対応）
- **行番号 / 折り返し** — 表示メニューから切替
- **検索** — `Ctrl+F`（インクリメンタル、Enter で次、Shift+Enter / Prev で前、Esc で終了）
- **Markdown プレビュー** — `Ctrl+P` で切替（Qt の Markdown レンダラ）
- **メニューのキーボード操作** — メニューを開いて ↑↓ で移動、Enter で決定
- **ダイアログのキーボード操作** — 終了/タブを閉じる確認は ←→（↑↓）でボタンを選び、Enter で決定（Esc で取り消し）
- **単一インスタンス** — `shiori file` は起動中のウィンドウにタブ追加
- **クロスプラットフォーム** — Linux (Wayland/X11) / macOS / Windows

> このリポジトリは以前の Rust + egui 実装を Qt6/QML に置き換えたものです
> （旧実装は git 履歴に残っています）。

## 使い方

```sh
shiori                      # 空のノート（前回のセッションを復元）
shiori file.txt             # ファイルを開く
shiori a.md b.txt           # 複数ファイルをタブで開く
shiori -n                   # セッションを復元せず新規
shiori --preview file.md    # Markdown プレビューで開く
shiori --find TEXT file.md  # 検索バーに TEXT を入れて開く
```

すでに起動していれば、`shiori file` は既存ウィンドウのタブとして開きます
（単一インスタンス）。

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

### Nix 以外（各 OS でビルド）

必要なもの: Qt 6.5+（`qtbase` / `qtdeclarative`）、CMake 3.21+、C++17 コンパイラ。
（Windows は MSVC か MinGW、macOS は Xcode CLT）

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel
```

#### Linux

```sh
sudo apt install qt6-base-dev qt6-declarative-dev cmake ninja-build   # Debian/Ubuntu の例
cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
./build/shiori
# インストール
cmake --install build --prefix ~/.local
```

#### macOS

```sh
brew install qt cmake
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build
open build/shiori.app
```

#### Windows（PowerShell / MSVC）

```powershell
# Qt をインストール後、Qt の bin に PATH を通しておく
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
.\build\Release\shiori.exe
```

配布用に Qt の DLL を同梱する場合:

```sh
macdeployqt build/shiori.app -qmldir=qml     # macOS
windeployqt --release --qmldir qml build/Release/shiori.exe   # Windows
```

#### 自動ビルド

`.github/workflows/build.yml` で Linux / macOS / Windows の
ビルド成果物（tarball / zip）を GitHub Actions が生成します。

## ショートカット

| キー | 動作 |
|---|---|
| `Ctrl+T` / `Ctrl+N` | 新しいタブ |
| `Ctrl+O` | ファイルを開く |
| `Ctrl+Tab` / `Ctrl+PageDown` | 次のタブ |
| `Ctrl+Shift+Tab` / `Ctrl+PageUp` | 前のタブ |
| `Ctrl+S` / `Ctrl+Shift+S` | 保存 / 名前を付けて保存 |
| `Ctrl+W` / `Ctrl+Q` | タブを閉じる / 終了 |
| `Ctrl+F` | 検索（Enter 次、Prev 前、Esc 終了） |
| `Ctrl+P` | Markdown プレビュー切替 |
| `Ctrl+B` / `Ctrl+Shift+B` | この行に栞 / ファイル栞 |
| `Ctrl+J` | 栞パネル |
| `Ctrl+=` / `Ctrl+Shift+Up` | 文字サイズ 拡大 |
| `Ctrl+-` / `Ctrl+Shift+Down` | 文字サイズ 縮小 |
| `Ctrl+0` | 文字サイズ 等倍 |
| メニューを開いて `↑↓` → `Enter` | メニュー操作 |
| 確認ダイアログで `←→`（`↑↓`） → `Enter` | ボタンの選択と決定（`Esc` で取り消し） |

## ライセンス

MIT
