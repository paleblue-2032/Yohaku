use std::path::{Path, PathBuf};

/// XDG 準拠のディレクトリ解決（config / state）。
pub fn project_dirs() -> directories::ProjectDirs {
    directories::ProjectDirs::from("dev", "paleblue", "shiori").expect("XDG directories")
}

pub fn config_dir() -> PathBuf {
    project_dirs().config_dir().to_path_buf()
}

pub fn state_dir() -> PathBuf {
    project_dirs()
        .state_dir()
        .map(Path::to_path_buf)
        .unwrap_or_else(config_dir)
}

pub fn ensure_dir(p: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(p)
}

/// バイト位置 -> 文字インデックス（egui の CCursor は文字単位）。
pub fn byte_to_char(text: &str, byte: usize) -> usize {
    let byte = byte.min(text.len());
    text[..byte].chars().count()
}

/// 文字インデックス -> バイト位置。
pub fn char_to_byte(text: &str, ch: usize) -> usize {
    text.char_indices()
        .nth(ch)
        .map(|(b, _)| b)
        .unwrap_or(text.len())
}

/// 0 始まりの行番号 -> その行頭のバイト位置。
pub fn line_to_byte(text: &str, line: usize) -> usize {
    let mut cur = 0usize;
    for (b, c) in text.char_indices() {
        if cur == line {
            return b;
        }
        if c == '\n' {
            cur += 1;
        }
    }
    text.len()
}

/// バイト位置 -> 0 始まりの行番号。
pub fn byte_to_line(text: &str, byte: usize) -> usize {
    let byte = byte.min(text.len());
    text[..byte].bytes().filter(|&b| b == b'\n').count()
}

/// テキストの総行数（最後の行も数える）。
pub fn line_count(text: &str) -> usize {
    if text.is_empty() {
        1
    } else {
        text.bytes().filter(|&b| b == b'\n').count() + 1
    }
}

/// 指定行の文字列（改行を含まない）を返す。栞一覧の抜粋表示に使う。
pub fn line_text(text: &str, line: usize) -> &str {
    let start = line_to_byte(text, line);
    let rest = &text[start..];
    let end = rest.find('\n').unwrap_or(rest.len());
    &rest[..end]
}
