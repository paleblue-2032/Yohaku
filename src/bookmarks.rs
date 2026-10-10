use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::util;

/// ファイル自体の栞（お気に入り）。
#[derive(Serialize, Deserialize, Clone, PartialEq)]
pub struct FileBookmark {
    pub key: String,
    pub title: String,
    pub path: Option<PathBuf>,
    pub draft_id: Option<String>,
}

/// 栞の永続ストア。
/// - `last_pos`: 自動栞（ファイルごとの最後のカーソル行）
/// - `line_bookmarks`: 手動で挟んだ行栞
/// - `files`: ファイル栞（お気に入り）
#[derive(Default, Serialize, Deserialize)]
pub struct BookmarkStore {
    pub last_pos: HashMap<String, usize>,
    pub line_bookmarks: HashMap<String, Vec<usize>>,
    pub files: Vec<FileBookmark>,
}

impl BookmarkStore {
    fn path() -> PathBuf {
        util::state_dir().join("bookmarks.json")
    }

    pub fn load() -> Self {
        std::fs::read_to_string(Self::path())
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) {
        let _ = util::ensure_dir(&util::state_dir());
        if let Ok(s) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(Self::path(), s);
        }
    }

    pub fn set_last_pos(&mut self, key: &str, line: usize) {
        self.last_pos.insert(key.to_string(), line);
    }

    pub fn last_pos(&self, key: &str) -> Option<usize> {
        self.last_pos.get(key).copied()
    }

    pub fn set_lines(&mut self, key: &str, lines: Vec<usize>) {
        if lines.is_empty() {
            self.line_bookmarks.remove(key);
        } else {
            self.line_bookmarks.insert(key.to_string(), lines);
        }
    }

    pub fn lines(&self, key: &str) -> Vec<usize> {
        self.line_bookmarks.get(key).cloned().unwrap_or_default()
    }

    pub fn is_file_bookmarked(&self, key: &str) -> bool {
        self.files.iter().any(|f| f.key == key)
    }

    /// ファイル栞の追加/削除。追加したら true。
    pub fn toggle_file(&mut self, key: String, title: String, path: Option<PathBuf>, draft_id: Option<String>) -> bool {
        if let Some(pos) = self.files.iter().position(|f| f.key == key) {
            self.files.remove(pos);
            false
        } else {
            self.files.push(FileBookmark { key, title, path, draft_id });
            true
        }
    }
}
