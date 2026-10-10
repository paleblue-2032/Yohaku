use serde::{Deserialize, Serialize};

use crate::util;

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
pub enum FontChoice {
    /// Noto Sans JP（日本語もラテンもこれ）
    Sans,
    /// egui 既定の等幅（ラテン）+ Noto Sans JP フォールバック
    Mono,
}

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
pub enum ThemeMode {
    Dark,
    Light,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Settings {
    pub font: FontChoice,
    pub font_size: f32,
    pub theme: ThemeMode,
    pub word_wrap: bool,
    pub tab_width: usize,
    pub show_line_numbers: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            font: FontChoice::Sans,
            font_size: 16.0,
            theme: ThemeMode::Dark,
            word_wrap: true,
            tab_width: 4,
            show_line_numbers: true,
        }
    }
}

impl Settings {
    fn path() -> std::path::PathBuf {
        util::config_dir().join("settings.json")
    }

    pub fn load() -> Self {
        std::fs::read_to_string(Self::path())
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) {
        let _ = util::ensure_dir(&util::config_dir());
        if let Ok(s) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(Self::path(), s);
        }
    }

    pub fn font_size_step(&mut self, delta: f32) {
        self.font_size = (self.font_size + delta).clamp(8.0, 48.0);
    }
}
