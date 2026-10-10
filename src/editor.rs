use egui::text::{CCursor, CCursorRange, LayoutJob, TextFormat};
use egui::{Color32, FontId, Margin, TextBuffer, TextEdit};

use crate::document::Document;
use crate::search::SearchState;
use crate::settings::{FontChoice, Settings};

/// 行番号・栞マーカー用のガター幅。
const GUTTER_W: i8 = 46;
const MATCH_BG: Color32 = Color32::from_rgba_premultiplied(255, 210, 40, 90);

pub struct EditorOutput {
    pub changed: bool,
    pub cursor_char: usize,
}

pub fn font_id(settings: &Settings) -> FontId {
    match settings.font {
        FontChoice::Sans => FontId::proportional(settings.font_size),
        FontChoice::Mono => FontId::monospace(settings.font_size),
    }
}

fn format(font_id: &FontId, background: Option<Color32>) -> TextFormat {
    TextFormat {
        font_id: font_id.clone(),
        color: Color32::PLACEHOLDER,
        background: background.unwrap_or(Color32::TRANSPARENT),
        ..Default::default()
    }
}

pub fn show(
    ui: &mut egui::Ui,
    doc: &mut Document,
    settings: &Settings,
    search: &SearchState,
) -> EditorOutput {
    let id = egui::Id::new(("shiori_editor", doc.uid));
    let fid = font_id(settings);

    let matches = search.matches.clone();
    let current = search.current_match();
    let qlen = search.query.len();
    let wrap = settings.word_wrap;

    let mut layouter = |ui: &egui::Ui, buf: &dyn TextBuffer, wrap_width: f32| {
        let text = buf.as_str();
        let mut job = LayoutJob::default();

        if matches.is_empty() {
            job.append(text, 0.0, format(&fid, None));
        } else {
            let mut pos = 0usize;
            for &m in &matches {
                if m >= text.len() {
                    break;
                }
                let end = (m + qlen).min(text.len());
                if m > pos {
                    job.append(&text[pos..m], 0.0, format(&fid, None));
                }
                let bg = if Some(m) == current {
                    ui.visuals().selection.bg_fill
                } else {
                    MATCH_BG
                };
                job.append(&text[m..end], 0.0, format(&fid, Some(bg)));
                pos = end;
            }
            if pos < text.len() {
                job.append(&text[pos..], 0.0, format(&fid, None));
            }
        }

        job.wrap.max_width = if wrap { wrap_width } else { f32::INFINITY };
        ui.painter().layout_job(job)
    };

    let margin = if settings.show_line_numbers {
        Margin {
            left: GUTTER_W,
            right: 10,
            top: 6,
            bottom: 6,
        }
    } else {
        Margin {
            left: 10,
            right: 10,
            top: 6,
            bottom: 6,
        }
    };

    let output = TextEdit::multiline(&mut doc.text)
        .id(id)
        .font(fid.clone())
        .desired_width(f32::INFINITY)
        .desired_rows(28)
        .margin(margin)
        .lock_focus(true)
        .layouter(&mut layouter)
        .show(ui);

    if settings.show_line_numbers {
        paint_gutter(ui, &output, doc);
    }

    let changed = output.response.response.changed();
    let cursor_char = output
        .cursor_range
        .map(|r| r.primary.index.0)
        .unwrap_or(doc.cursor_char);

    EditorOutput {
        changed,
        cursor_char,
    }
}

/// 行番号と、栞が挟まれた行の ◆ を描画する。
fn paint_gutter(ui: &egui::Ui, output: &egui::text_edit::TextEditOutput, doc: &Document) {
    let painter = ui.painter();
    let clip = ui.clip_rect();
    let galley_pos = output.galley_pos;
    let gutter_right = galley_pos.x - 8.0;
    let gutter_left = output.response.response.rect.left();
    let num_font = FontId::monospace(11.0);
    let mark_font = FontId::proportional(11.0);
    let num_color = ui.visuals().weak_text_color();
    let mark_color = Color32::from_rgb(230, 180, 80);

    let mut line_no = 1usize;
    for row in &output.galley.rows {
        let y = galley_pos.y + row.pos.y;
        let visible = y + row.size.y > clip.top() - 4.0 && y < clip.bottom() + 4.0;
        if visible {
            painter.text(
                egui::pos2(gutter_right, y),
                egui::Align2::RIGHT_TOP,
                line_no.to_string(),
                num_font.clone(),
                num_color,
            );
            if doc.has_bookmark(line_no - 1) {
                painter.text(
                    egui::pos2(gutter_left + 6.0, y),
                    egui::Align2::LEFT_TOP,
                    "\u{25C6}",
                    mark_font.clone(),
                    mark_color,
                );
            }
        }
        if row.ends_with_newline {
            line_no += 1;
        }
    }
}

/// 指定行の先頭にカーソルを移動し、スクロールを追従させる。
pub fn jump_to_line(ctx: &egui::Context, id: egui::Id, text: &str, line: usize) {
    let byte = crate::util::line_to_byte(text, line);
    let ch = crate::util::byte_to_char(text, byte);
    if let Some(mut state) = egui::text_edit::TextEditState::load(ctx, id) {
        state
            .cursor
            .set_char_range(Some(CCursorRange::one(CCursor::new(ch))));
        state.store(ctx, id);
    }
    ctx.memory_mut(|m| m.request_focus(id));
}

/// 指定バイト範囲を選択状態にしてカーソルを移動する（検索ジャンプ用）。
pub fn select_byte_range(ctx: &egui::Context, id: egui::Id, text: &str, start: usize, end: usize) {
    let a = crate::util::byte_to_char(text, start);
    let b = crate::util::byte_to_char(text, end);
    if let Some(mut state) = egui::text_edit::TextEditState::load(ctx, id) {
        state
            .cursor
            .set_char_range(Some(CCursorRange::two(CCursor::new(a), CCursor::new(b))));
        state.store(ctx, id);
    }
    ctx.memory_mut(|m| m.request_focus(id));
}
