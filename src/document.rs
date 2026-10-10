use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::PathBuf;

/// 1 つのタブ = 1 つの文書。
#[derive(Clone)]
pub struct Document {
    /// 一意 ID（TextEdit の Id 生成に使う）。
    pub uid: u64,
    pub path: Option<PathBuf>,
    pub text: String,
    pub dirty: bool,
    /// カーソル位置（文字インデックス）。
    pub cursor_char: usize,
    /// 無題ノートの安定 ID（ファイル栞やドラフトのキー）。
    pub untitled_id: Option<String>,
    /// 手動で挟んだ栞（0 始まりの行番号、昇順）。
    pub line_bookmarks: Vec<usize>,
}

impl Document {
    /// 無題ノート。`id` はセッションを跨いで安定な文字列（例: `untitled-<millis>`）。
    pub fn untitled(uid: u64, id: String) -> Self {
        Self {
            uid,
            path: None,
            text: String::new(),
            dirty: false,
            cursor_char: 0,
            untitled_id: Some(id),
            line_bookmarks: Vec::new(),
        }
    }

    pub fn from_path(uid: u64, path: PathBuf) -> std::io::Result<Self> {
        let text = std::fs::read_to_string(&path)?;
        Ok(Self {
            uid,
            path: Some(path),
            text,
            dirty: false,
            cursor_char: 0,
            untitled_id: None,
            line_bookmarks: Vec::new(),
        })
    }

    /// 栞（位置記憶・行栞・ファイル栞）のキー。
    pub fn key(&self) -> String {
        self.path
            .as_ref()
            .map(|p| p.to_string_lossy().to_string())
            .or_else(|| self.untitled_id.clone())
            .unwrap_or_else(|| format!("doc-{}", self.uid))
    }

    /// 自動保存ドラフトのキー。無題は安定 ID、パス付きはパスのハッシュ。
    pub fn draft_key(&self) -> String {
        if let Some(id) = &self.untitled_id {
            id.clone()
        } else if let Some(p) = &self.path {
            let mut h = DefaultHasher::new();
            p.hash(&mut h);
            format!("path-{:x}", h.finish())
        } else {
            format!("doc-{}", self.uid)
        }
    }

    /// パスのファイル名。無題なら "untitled"（保存ダイアログの既定名に使う）。
    pub fn file_name(&self) -> String {
        if let Some(p) = &self.path {
            p.file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| p.to_string_lossy().to_string())
        } else {
            "untitled".to_string()
        }
    }

    /// UI 表示用のタイトル。無題は言語に応じたラベルを使う。
    pub fn display_title(&self, untitled: &str) -> String {
        if let Some(p) = &self.path {
            p.file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| p.to_string_lossy().to_string())
        } else {
            untitled.to_string()
        }
    }

    pub fn is_markdown(&self) -> bool {
        self.path
            .as_ref()
            .and_then(|p| p.extension())
            .map(|e| {
                let e = e.to_string_lossy().to_ascii_lowercase();
                e == "md" || e == "markdown"
            })
            .unwrap_or(false)
    }

    pub fn save(&mut self) -> std::io::Result<()> {
        let path = self
            .path
            .clone()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "保存先がありません"))?;
        std::fs::write(&path, &self.text)?;
        self.dirty = false;
        crate::session::remove_draft(&self.draft_key());
        Ok(())
    }

    pub fn save_as(&mut self, path: PathBuf) -> std::io::Result<()> {
        std::fs::write(&path, &self.text)?;
        let old_key = self.draft_key();
        self.path = Some(path);
        self.untitled_id = None;
        self.dirty = false;
        crate::session::remove_draft(&old_key);
        Ok(())
    }

    /// 指定行の栞をトグルする。
    pub fn toggle_line_bookmark(&mut self, line: usize) {
        if let Some(pos) = self.line_bookmarks.iter().position(|&l| l == line) {
            self.line_bookmarks.remove(pos);
        } else {
            self.line_bookmarks.push(line);
            self.line_bookmarks.sort_unstable();
        }
    }

    pub fn has_bookmark(&self, line: usize) -> bool {
        self.line_bookmarks.binary_search(&line).is_ok()
    }

    /// カーソルのある行（0 始まり）。
    pub fn cursor_line(&self) -> usize {
        let byte = crate::util::char_to_byte(&self.text, self.cursor_char);
        crate::util::byte_to_line(&self.text, byte)
    }
}
