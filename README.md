# yohaku

Markdownプレビュー機能付きの、シンプルで機能美に優れたメモ帳エディタ。**Qt 6 / QML** 実装。

## 特徴

- **標準ショートカットがそのまま効く** — Ctrl+C / V / X / Z / S など
- **タブ** — 複数ファイルをタブで。`Ctrl+T` で新しいタブ、`Ctrl+Tab` で切替。**起動時は常に新しいタブ**で開始（前回のタブは復元しない）
- **栞** — 自動（最後のカーソル位置を記憶して次回そこへ戻る）、手動（`Ctrl+B`）、ファイル栞（`Ctrl+Shift+B`）
- **日本語入力** — fcitx5 などの IME からそのまま入力できる
- **多言語 UI** — 英語 / 日本語（既定は英語、設定メニューから切替）
- **テーマ & アクセントカラー** — ダーク / ライト、5 色のアクセント
- **透過** — 設定メニューから なし / 弱 / 中 / 強。外周（メニュー・タブ・ステータス・余白）より**入力欄を少しだけ濃く**して読みやすくしています。※コンポジタ側にブラー（すりガラス）が無い環境では、強い透過は文字が読みづらくなります（niri 25.08 は blur 非対応）
- **行番号 / 折り返し** — 表示メニューから切替
- **検索** — `Ctrl+F`（インクリメンタル、Enter で次、Shift+Enter / Prev で前、Esc で終了）
- **Markdown プレビュー** — `Ctrl+P` で切替。GFM として解釈し、見出しの罫線・コードの背景・引用・表・リンク色を GitHub 風に整形。**プレビュー中は編集できません**（閲覧専用）。`↑↓` / `PgUp` / `PgDn` / `Home` / `End` でスクロール、`#見出し` へのリンクはプレビュー内ジャンプ、外部リンクは既定のブラウザで開きます。フォントは設定メニューから サンセリフ / セリフ / 等幅 を選べます
- **メニューのキーボード操作** — メニューを開いて ↑↓ で移動、Enter で決定
- **ダイアログのキーボード操作** — 終了/タブを閉じる確認は ←→（↑↓）でボタンを選び、Enter で決定（Esc で取り消し）
- **単一インスタンス** — `yohaku file` は起動中のウィンドウにタブ追加
- **クロスプラットフォーム** — Linux (Wayland/X11) / macOS / Windows

> このリポジトリは以前の Rust + egui 実装を Qt6/QML に置き換えたものです
> （旧実装は git 履歴に残っています）。

## 使い方

```sh
yohaku                      # 新しいノート（起動時は常に新規タブ）
yohaku file.txt             # ファイルを開く
yohaku a.md b.txt           # 複数ファイルをタブで開く
yohaku --preview file.md    # Markdown プレビューで開く
yohaku --find TEXT file.md  # 検索バーに TEXT を入れて開く
```

すでに起動していれば、`yohaku file` は既存ウィンドウのタブとして開きます
（単一インスタンス）。

## 必要なもの

- Qt 6.5 以上（`qtbase` / `qtdeclarative`）
- CMake 3.21 以上、Ninja、C++17 コンパイラ

## インストール

### 1. ワンライナー（いちばん手軽）

**macOS / Linux**

```sh
curl -fsSL https://raw.githubusercontent.com/paleblue-2032/yohaku/main/scripts/install.sh | bash
```

- macOS: `Yohaku.app` を「アプリケーション」へ入れ、quarantine を外して Launchpad から起動できるようにします
- Linux: `~/.local/opt/yohaku` に展開し、`~/.local/bin/yohaku` と `.desktop` / アイコンを登録します（要 Qt6）

**Windows（PowerShell）**

```powershell
irm https://raw.githubusercontent.com/paleblue-2032/yohaku/main/scripts/install.ps1 | iex
```

`%LOCALAPPDATA%\Programs\Yohaku` へ入れて PATH とスタートメニューに登録します。
デスクトップにもショートカットが欲しいときは事前に `$env:YOHAKU_DESKTOP_SHORTCUT=1` を設定してください。

バージョンを指定したいときは `YOHAKU_VERSION=0.1.0`（PowerShell は `$env:YOHAKU_VERSION`）を付けます。

### 2. Nix / NixOS（宣言的・推奨）

**試すだけ（インストールしない）**

```sh
nix run github:paleblue-2032/yohaku
```

**ユーザー環境に入れる**

```sh
nix profile install github:paleblue-2032/yohaku
# 削除: nix profile remove yohaku
```

**宣言的に入れる（NixOS / home-manager）**

`flake.nix` の inputs に追加:

```nix
yohaku = {
  url = "github:paleblue-2032/yohaku";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

`home-manager` のパッケージ一覧に追記:

```nix
home.packages = [ inputs.yohaku.packages.${pkgs.system}.yohaku ];
```

あとは反映:

```sh
sudo nixos-rebuild switch --flake <your-flake>#<host>
```

### 3. リリースから手動で

[Releases](https://github.com/paleblue-2032/yohaku/releases) にビルド済みの成果物があります。

| OS | ファイル | 使い方 |
|---|---|---|
| macOS (Apple Silicon) | `yohaku-macos-arm64.zip` | 展開して `Yohaku.app` をアプリケーションへ（Intel Mac は下の「自分でビルドする」から） |
| Windows | `yohaku-windows-x86_64.zip` | 展開して `yohaku.exe`（Qt の DLL 同梱） |
| Linux | `yohaku-linux-x86_64.tar.gz` | 展開して `./install.sh`（要 Qt6） |

### 4. 自分でビルドする

必要なもの: Qt 6.5+（`qtbase` / `qtdeclarative`）、CMake 3.21+、C++17 コンパイラ。

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel
```

**Linux**

```sh
sudo apt install qt6-base-dev qt6-declarative-dev cmake ninja-build   # Debian/Ubuntu の例
cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
./build/yohaku
cmake --install build --prefix ~/.local     # インストールする場合
```

**macOS**

```sh
brew install qt cmake
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build
open build/yohaku.app
```

**Windows（PowerShell / MSVC）**

```powershell
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
.\build\Release\yohaku.exe
```

配布用に Qt を同梱する場合:

```sh
macdeployqt build/yohaku.app -qmldir=qml                      # macOS
windeployqt --release --qmldir qml build/Release/yohaku.exe   # Windows
```

### ランチャ / 検索への表示

パッケージに `.desktop` とアイコンを同梱しています:

- `share/applications/yohaku.desktop`
- `share/icons/hicolor/scalable/apps/yohaku.svg`

プロファイルの `share` は `XDG_DATA_DIRS` に含まれるため、2 / 3 の方法で入れると
GNOME のアクティビティ検索や Noctalia などのランチャに **Yohaku** が表示されます。

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
| `Ctrl++` / `Ctrl+=` / `Ctrl+Shift+Up` | 文字サイズ 拡大 |
| `Ctrl+-` / `Ctrl+_` / `Ctrl+Shift+Down` | 文字サイズ 縮小 |
| `Ctrl+0` | 文字サイズ 等倍 |
| `Ctrl+Y` / `Ctrl+Shift+Z` | やり直し（redo） |

文字サイズのキーはキーイベントを直接見ているため、**JIS 配列でも効きます**
（JIS では `=` が Shift+-、`+` が Shift+; にあり、一般的なショートカット指定だと一致しません）。
| メニューを開いて `↑↓` → `Enter` | メニュー操作 |
| 確認ダイアログで `←→`（`↑↓`） → `Enter` | ボタンの選択と決定（`Esc` で取り消し） |

## キーのカスタマイズ

`~/.config/yohaku/keymap.json` でショートカットを変更できます（初回起動時に雛形を書き出します）。
ファイルを保存すると**起動中でも反映**されます。

```json
{
  "save": ["Ctrl+S", "Ctrl+Shift+S"],
  "newTab": "Ctrl+T",
  "preview": "Ctrl+Shift+P",
  "closeTab": []
}
```

- 値は文字列か配列。配列で複数割り当て
- 空配列 / 空文字にするとその割り当てを外せます
- 指定できるアクション: `newTab` `open` `save` `saveAs` `closeTab` `quit` `find` `preview`
  `undo` `redo` `bookmarkLine` `bookmarkFile` `bookmarkPanel` `nextTab` `prevTab`
- 文字サイズ（`Ctrl+=` / `Ctrl+-` / `Ctrl+0`）はキー配列に依存せず動く必要があるため、
  この設定の対象外です

## ライセンス

MIT
