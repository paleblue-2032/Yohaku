use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::util;

/// 1 タブ分の永続状態。
#[derive(Serialize, Deserialize, Clone)]
pub struct TabState {
    pub path: Option<PathBuf>,
    pub draft_id: Option<String>,
}

/// セッション（開いていたタブ）とドラフトの保存・復元。
#[derive(Default, Serialize, Deserialize)]
pub struct Session {
    pub tabs: Vec<TabState>,
    pub active: usize,
}

impl Session {
    fn path() -> PathBuf {
        util::state_dir().join("session.json")
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
}

fn drafts_dir() -> PathBuf {
    util::state_dir().join("drafts")
}

pub fn draft_path(id: &str) -> PathBuf {
    drafts_dir().join(format!("{id}.txt"))
}

pub fn write_draft(id: &str, text: &str) {
    let _ = util::ensure_dir(&drafts_dir());
    let _ = std::fs::write(draft_path(id), text);
}

pub fn read_draft(id: &str) -> Option<String> {
    std::fs::read_to_string(draft_path(id)).ok()
}

pub fn remove_draft(id: &str) {
    let _ = std::fs::remove_file(draft_path(id));
}
