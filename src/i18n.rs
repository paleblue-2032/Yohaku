use serde::{Deserialize, Serialize};

/// UI の表示言語。既定は英語。
#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
pub enum Lang {
    En,
    Ja,
}

impl Default for Lang {
    fn default() -> Self {
        Lang::En
    }
}

/// 表示文字列の集合。
pub struct S {
    pub title: &'static str,
    // menus
    pub file: &'static str,
    pub view: &'static str,
    pub bookmarks: &'static str,
    pub search: &'static str,
    pub settings: &'static str,
    // file menu
    pub new: &'static str,
    pub open: &'static str,
    pub save: &'static str,
    pub save_as: &'static str,
    pub close_tab: &'static str,
    pub quit: &'static str,
    // view menu
    pub preview: &'static str,
    pub word_wrap: &'static str,
    pub line_numbers: &'static str,
    pub theme: &'static str,
    pub dark: &'static str,
    pub light: &'static str,
    pub system: &'static str,
    pub font: &'static str,
    pub sans: &'static str,
    pub mono: &'static str,
    pub zoom_in: &'static str,
    pub zoom_out: &'static str,
    pub zoom_reset: &'static str,
    pub accent: &'static str,
    pub language: &'static str,
    pub english: &'static str,
    pub japanese: &'static str,
    // bookmarks menu
    pub bookmark_line: &'static str,
    pub bookmark_file_add: &'static str,
    pub bookmark_file_remove: &'static str,
    pub bookmark_panel: &'static str,
    // search
    pub find: &'static str,
    pub find_hint: &'static str,
    pub prev: &'static str,
    pub next: &'static str,
    pub close: &'static str,
    // tabs / doc
    pub new_tab_hint: &'static str,
    pub untitled: &'static str,
    // panel
    pub this_file_bookmarks: &'static str,
    pub no_line_bookmarks: &'static str,
    pub file_bookmarks: &'static str,
    pub no_file_bookmarks: &'static str,
    // status
    pub line: &'static str,
    pub col: &'static str,
    pub edit: &'static str,
    pub preview_mode: &'static str,
    pub empty_hint: &'static str,
    // dialogs ({} はファイル名に置換)
    pub unsaved_title: &'static str,
    pub unsaved_body: &'static str,
    pub dont_save: &'static str,
    pub cancel: &'static str,
    pub quit_title: &'static str,
    pub quit_body: &'static str,
    pub save_and_quit: &'static str,
    pub quit_without_saving: &'static str,
    // status messages ({} は詳細に置換)
    pub saved: &'static str,
    pub save_failed: &'static str,
    pub open_failed: &'static str,
    pub bm_added: &'static str,
    pub bm_removed: &'static str,
    pub fbm_added: &'static str,
    pub fbm_removed: &'static str,
    // help
    pub help: &'static str,
}

pub const EN: S = S {
    title: "shiori",
    file: "File",
    view: "View",
    bookmarks: "Bookmarks",
    search: "Search",
    settings: "Settings",
    new: "New",
    open: "Open…",
    save: "Save",
    save_as: "Save As…",
    close_tab: "Close Tab",
    quit: "Quit",
    preview: "Markdown Preview",
    word_wrap: "Word Wrap",
    line_numbers: "Line Numbers",
    theme: "Theme",
    dark: "Dark",
    light: "Light",
    system: "System",
    font: "Font",
    sans: "Sans",
    mono: "Mono",
    zoom_in: "Zoom In",
    zoom_out: "Zoom Out",
    zoom_reset: "Reset Zoom",
    accent: "Accent Color",
    language: "Language",
    english: "English",
    japanese: "日本語",
    bookmark_line: "Toggle Bookmark on This Line",
    bookmark_file_add: "Bookmark This File",
    bookmark_file_remove: "Remove File Bookmark",
    bookmark_panel: "Bookmarks Panel",
    find: "Find…",
    find_hint: "Search",
    prev: "Prev",
    next: "Next",
    close: "Close",
    new_tab_hint: "New tab (Ctrl+N)",
    untitled: "Untitled",
    this_file_bookmarks: "Bookmarks in this file",
    no_line_bookmarks: "(Ctrl+B to bookmark a line)",
    file_bookmarks: "File bookmarks",
    no_file_bookmarks: "(Ctrl+Shift+B to add)",
    line: "line",
    col: "col",
    edit: "Edit",
    preview_mode: "Preview",
    empty_hint: "Open a file (Ctrl+O) or create a new one (Ctrl+N)",
    unsaved_title: "Unsaved changes",
    unsaved_body: "Save changes to “{}”?",
    dont_save: "Don’t Save",
    cancel: "Cancel",
    quit_title: "Unsaved changes",
    quit_body: "You have unsaved changes. Quit anyway?",
    save_and_quit: "Save and Quit",
    quit_without_saving: "Quit Without Saving",
    saved: "Saved",
    save_failed: "Save failed: {}",
    open_failed: "Could not open {}",
    bm_added: "Bookmark added",
    bm_removed: "Bookmark removed",
    fbm_added: "Added to file bookmarks",
    fbm_removed: "Removed from file bookmarks",
    help: "\
shiori — a simple notepad editor with bookmarks

Usage:
  shiori [options] [files...]

Options:
  -n, --new     Start with a new note (do not restore previous tabs)
  -h, --help    Show this help
  -V, --version Show version

Opening files creates one tab per file. If shiori is already running,
files are added as tabs to the existing window.
",
};

pub const JA: S = S {
    title: "shiori",
    file: "ファイル",
    view: "表示",
    bookmarks: "栞",
    search: "検索",
    settings: "設定",
    new: "新規",
    open: "開く…",
    save: "保存",
    save_as: "名前を付けて保存…",
    close_tab: "タブを閉じる",
    quit: "終了",
    preview: "Markdown プレビュー",
    word_wrap: "折り返し",
    line_numbers: "行番号",
    theme: "テーマ",
    dark: "ダーク",
    light: "ライト",
    system: "システム",
    font: "フォント",
    sans: "サンセリフ",
    mono: "等幅",
    zoom_in: "拡大",
    zoom_out: "縮小",
    zoom_reset: "等倍",
    accent: "アクセントカラー",
    language: "言語",
    english: "English",
    japanese: "日本語",
    bookmark_line: "この行に栞を挟む/外す",
    bookmark_file_add: "このファイルを栞に追加",
    bookmark_file_remove: "ファイル栞から外す",
    bookmark_panel: "栞パネル",
    find: "検索…",
    find_hint: "検索語",
    prev: "前",
    next: "次",
    close: "閉じる",
    new_tab_hint: "新規タブ (Ctrl+N)",
    untitled: "無題",
    this_file_bookmarks: "このファイルの栞",
    no_line_bookmarks: "（Ctrl+B でこの行に栞）",
    file_bookmarks: "ファイル栞",
    no_file_bookmarks: "（Ctrl+Shift+B で追加）",
    line: "行",
    col: "列",
    edit: "編集",
    preview_mode: "プレビュー",
    empty_hint: "ファイルを開く（Ctrl+O）か、Ctrl+N で新規作成",
    unsaved_title: "未保存の変更",
    unsaved_body: "「{}」を保存しますか？",
    dont_save: "保存しない",
    quit_title: "未保存の変更があります",
    quit_body: "保存していない変更があります。終了しますか？",
    save_and_quit: "保存して終了",
    quit_without_saving: "保存せず終了",
    cancel: "キャンセル",
    saved: "保存しました",
    save_failed: "保存失敗: {}",
    open_failed: "開けません: {}",
    bm_added: "栞を挟みました",
    bm_removed: "栞を外しました",
    fbm_added: "ファイル栞に追加しました",
    fbm_removed: "ファイル栞から外しました",
    help: "\
shiori — 栞付きのシンプルなメモ帳エディタ

使い方:
  shiori [オプション] [ファイル...]

オプション:
  -n, --new     新しいノートで開始（前回のタブを復元しない）
  -h, --help    このヘルプを表示
  -V, --version バージョンを表示

ファイルを指定すると各ファイルをタブで開く。すでに起動中なら
既存のウィンドウにタブとして追加する。
",
};

pub fn get(l: Lang) -> &'static S {
    match l {
        Lang::En => &EN,
        Lang::Ja => &JA,
    }
}
