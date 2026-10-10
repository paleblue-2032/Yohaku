use std::path::PathBuf;
use std::sync::mpsc::Receiver;
use std::time::{SystemTime, UNIX_EPOCH};

use egui::{Align, Align2, Key, Modifiers, RichText, ViewportCommand};

use crate::bookmarks::BookmarkStore;
use crate::document::Document;
use crate::editor;
use crate::ipc;
use crate::search::SearchState;
use crate::session::{self, Session, TabState};
use crate::settings::{FontChoice, Settings, ThemeMode};
use crate::theme;
use crate::util;

fn consume(ctx: &egui::Context, mods: Modifiers, key: Key) -> bool {
    ctx.input_mut(|i| i.consume_shortcut(&egui::KeyboardShortcut::new(mods, key)))
}

fn now_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}

pub struct ShioriApp {
    docs: Vec<Document>,
    active: usize,
    settings: Settings,
    bookmarks: BookmarkStore,
    search: SearchState,
    preview: bool,
    show_bookmarks: bool,
    status: Option<String>,
    ipc_rx: Option<Receiver<Vec<PathBuf>>>,
    md_cache: egui_commonmark::CommonMarkCache,
    next_uid: u64,
    confirm_close: Option<usize>,
    confirm_quit: bool,
    pending_jump: Option<usize>,
    last_autosave: f64,
    skip_save_state: bool,
    last_title: String,
}

impl ShioriApp {
    pub fn new(
        cc: &eframe::CreationContext<'_>,
        files: Vec<PathBuf>,
        force_new: bool,
        ipc_rx: Receiver<Vec<PathBuf>>,
    ) -> Self {
        let settings = Settings::load();
        theme::apply(
            &cc.egui_ctx,
            settings.theme,
            settings.font,
            settings.font_size,
        );

        let mut app = Self {
            docs: Vec::new(),
            active: 0,
            settings,
            bookmarks: BookmarkStore::load(),
            search: SearchState::default(),
            preview: false,
            show_bookmarks: false,
            status: None,
            ipc_rx: Some(ipc_rx),
            md_cache: Default::default(),
            next_uid: 1,
            confirm_close: None,
            confirm_quit: false,
            pending_jump: None,
            last_autosave: 0.0,
            skip_save_state: false,
            last_title: String::new(),
        };

        if !files.is_empty() && !force_new {
            for f in files {
                app.open_path(f);
            }
        } else {
            app.restore_session();
        }
        if app.docs.is_empty() {
            app.new_doc();
        }
        app
    }

    // ---- 文書操作 -------------------------------------------------------

    fn alloc_uid(&mut self) -> u64 {
        self.next_uid += 1;
        self.next_uid
    }

    fn set_status(&mut self, msg: String) {
        self.status = Some(msg);
    }

    fn new_doc(&mut self) {
        let uid = self.alloc_uid();
        let id = format!("untitled-{}", now_millis());
        self.docs.push(Document::untitled(uid, id));
        self.active = self.docs.len() - 1;
        self.preview = false;
    }

    fn open_path(&mut self, path: PathBuf) {
        let canonical = path.canonicalize().unwrap_or_else(|_| path.clone());
        if let Some(i) = self.docs.iter().position(|d| {
            d.path
                .as_ref()
                .map(|p| p == &canonical || p == &path)
                .unwrap_or(false)
        }) {
            self.active = i;
            return;
        }

        let uid = self.alloc_uid();
        match Document::from_path(uid, canonical) {
            Ok(mut doc) => {
                let key = doc.key();
                doc.line_bookmarks = self.bookmarks.lines(&key);
                let dk = doc.draft_key();
                if let Some(draft) = session::read_draft(&dk) {
                    if draft != doc.text {
                        doc.text = draft;
                        doc.dirty = true;
                    }
                }
                self.pending_jump = self.bookmarks.last_pos(&key);
                self.docs.push(doc);
                self.active = self.docs.len() - 1;
                self.preview = false;
            }
            Err(e) => self.set_status(format!("開けません: {} ({e})", path.display())),
        }
    }

    fn restore_session(&mut self) {
        let s = Session::load();
        for t in &s.tabs {
            if let Some(p) = &t.path {
                self.open_path(p.clone());
            } else if let Some(id) = &t.draft_id {
                let uid = self.alloc_uid();
                let mut doc = Document::untitled(uid, id.clone());
                if let Some(text) = session::read_draft(id) {
                    doc.text = text;
                }
                let key = doc.key();
                doc.line_bookmarks = self.bookmarks.lines(&key);
                self.docs.push(doc);
            }
        }
        if s.active < self.docs.len() {
            self.active = s.active;
        }
    }

    fn request_close(&mut self, i: usize) {
        if self.docs.get(i).map(|d| d.dirty).unwrap_or(false) {
            self.confirm_close = Some(i);
        } else {
            self.close_doc(i);
        }
    }

    fn close_doc(&mut self, i: usize) {
        if i >= self.docs.len() {
            return;
        }
        let doc = self.docs.remove(i);
        let key = doc.key();
        self.bookmarks.set_last_pos(&key, doc.cursor_line());
        self.bookmarks.set_lines(&key, doc.line_bookmarks.clone());
        self.bookmarks.save();
        if self.active >= self.docs.len() && !self.docs.is_empty() {
            self.active = self.docs.len() - 1;
        }
    }

    fn next_tab(&mut self, delta: i32) {
        if self.docs.is_empty() {
            return;
        }
        let n = self.docs.len() as i32;
        self.active = (((self.active as i32 + delta) % n + n) % n) as usize;
    }

    fn save_active(&mut self) {
        let a = self.active;
        let has_path = self.docs.get(a).map(|d| d.path.is_some()).unwrap_or(false);
        if !has_path {
            self.save_as_active();
            return;
        }
        let res = self.docs.get_mut(a).map(|d| d.save());
        match res {
            Some(Ok(())) => self.set_status("保存しました".into()),
            Some(Err(e)) => self.set_status(format!("保存失敗: {e}")),
            None => {}
        }
    }

    fn save_as_active(&mut self) {
        let a = self.active;
        let name = self
            .docs
            .get(a)
            .map(|d| d.title())
            .unwrap_or_else(|| "untitled.txt".into());
        let dialog = rfd::FileDialog::new()
            .set_title("名前を付けて保存")
            .set_file_name(name);
        if let Some(p) = dialog.save_file() {
            let res = self.docs.get_mut(a).map(|d| d.save_as(p));
            match res {
                Some(Ok(())) => self.set_status("保存しました".into()),
                Some(Err(e)) => self.set_status(format!("保存失敗: {e}")),
                None => {}
            }
        }
    }

    fn open_dialog(&mut self) {
        if let Some(paths) = rfd::FileDialog::new().set_title("開く").pick_files() {
            for p in paths {
                self.open_path(p);
            }
        }
    }

    fn toggle_bookmark_line(&mut self) {
        let a = self.active;
        let mut info = None;
        if let Some(doc) = self.docs.get_mut(a) {
            let line = doc.cursor_line();
            doc.toggle_line_bookmark(line);
            info = Some((doc.key(), doc.line_bookmarks.clone(), doc.has_bookmark(line)));
        }
        if let Some((key, lines, on)) = info {
            self.bookmarks.set_lines(&key, lines);
            self.bookmarks.save();
            self.set_status(if on {
                "栞を挟みました".into()
            } else {
                "栞を外しました".into()
            });
        }
    }

    fn toggle_file_bookmark(&mut self) {
        let a = self.active;
        let info = self
            .docs
            .get(a)
            .map(|d| (d.key(), d.title(), d.path.clone(), d.untitled_id.clone()));
        if let Some((key, title, path, uid)) = info {
            let added = self.bookmarks.toggle_file(key, title, path, uid);
            self.bookmarks.save();
            self.set_status(if added {
                "ファイル栞に追加しました".into()
            } else {
                "ファイル栞から外しました".into()
            });
        }
    }

    // ---- 永続化 ---------------------------------------------------------

    fn save_state(&mut self, write_drafts: bool) {
        let entries: Vec<(String, usize, Vec<usize>, String, Option<String>)> = self
            .docs
            .iter()
            .map(|d| {
                let need = d.dirty || d.path.is_none();
                let text = if need { Some(d.text.clone()) } else { None };
                (
                    d.key(),
                    d.cursor_line(),
                    d.line_bookmarks.clone(),
                    d.draft_key(),
                    text,
                )
            })
            .collect();

        for (key, line, lines, dk, text) in entries {
            self.bookmarks.set_last_pos(&key, line);
            self.bookmarks.set_lines(&key, lines);
            if write_drafts {
                match text {
                    Some(t) => session::write_draft(&dk, &t),
                    None => session::remove_draft(&dk),
                }
            }
        }

        let tabs: Vec<TabState> = self
            .docs
            .iter()
            .map(|d| TabState {
                path: d.path.clone(),
                draft_id: d.untitled_id.clone(),
            })
            .collect();
        Session {
            tabs,
            active: self.active,
        }
        .save();
        self.bookmarks.save();
        self.settings.save();
    }

    fn finish_quit(&mut self, ctx: &egui::Context, save: bool) {
        if save {
            for i in 0..self.docs.len() {
                if self.docs[i].path.is_some() && self.docs[i].dirty {
                    let _ = self.docs[i].save();
                }
            }
            self.save_state(true);
        } else {
            for i in 0..self.docs.len() {
                if self.docs[i].dirty || self.docs[i].path.is_none() {
                    session::remove_draft(&self.docs[i].draft_key());
                }
            }
            self.save_state(false);
        }
        self.skip_save_state = true;
        ctx.send_viewport_cmd(ViewportCommand::Close);
    }

    fn request_quit(&mut self, ctx: &egui::Context) {
        if self.docs.iter().any(|d| d.dirty) {
            self.confirm_quit = true;
        } else {
            self.save_state(true);
            ctx.send_viewport_cmd(ViewportCommand::Close);
        }
    }

    fn refresh_search(&mut self) {
        if !self.search.open {
            return;
        }
        let active = self.active;
        let Self { docs, search, .. } = self;
        if let Some(doc) = docs.get(active) {
            search.update(&doc.text);
        }
    }

    // ---- IPC / 入力 -----------------------------------------------------

    fn poll_ipc(&mut self) {
        let paths: Vec<PathBuf> = self
            .ipc_rx
            .as_ref()
            .map(|rx| rx.try_iter().flatten().collect())
            .unwrap_or_default();
        for p in paths {
            self.open_path(p);
        }
    }

    fn handle_close_request(&mut self, ctx: &egui::Context) {
        if ctx.input(|i| i.viewport().close_requested()) && self.docs.iter().any(|d| d.dirty) {
            ctx.send_viewport_cmd(ViewportCommand::CancelClose);
            self.confirm_quit = true;
        }
    }

    fn handle_shortcuts(&mut self, ctx: &egui::Context) {
        let cmd = Modifiers::COMMAND;
        let cmd_shift = Modifiers {
            command: true,
            shift: true,
            ..Default::default()
        };

        if consume(ctx, cmd, Key::N) {
            self.new_doc();
        }
        if consume(ctx, cmd, Key::O) {
            self.open_dialog();
        }
        if consume(ctx, cmd_shift, Key::S) {
            self.save_as_active();
        }
        if consume(ctx, cmd, Key::S) {
            self.save_active();
        }
        if consume(ctx, cmd, Key::W) {
            let a = self.active;
            self.request_close(a);
        }
        if consume(ctx, cmd, Key::Q) {
            self.request_quit(ctx);
        }
        if consume(ctx, cmd, Key::F) {
            self.search.open = true;
            self.search.focus = true;
        }
        if consume(ctx, cmd_shift, Key::B) {
            self.toggle_file_bookmark();
        }
        if consume(ctx, cmd, Key::B) {
            self.toggle_bookmark_line();
        }
        if consume(ctx, cmd, Key::J) {
            self.show_bookmarks = !self.show_bookmarks;
        }
        if consume(ctx, cmd, Key::P) {
            self.preview = !self.preview;
        }
        if consume(ctx, cmd, Key::Equals) || consume(ctx, cmd, Key::Plus) {
            self.settings.font_size_step(1.0);
        }
        if consume(ctx, cmd, Key::Minus) {
            self.settings.font_size_step(-1.0);
        }
        if consume(ctx, cmd, Key::Num0) {
            self.settings.font_size = 16.0;
        }
        if consume(ctx, cmd_shift, Key::Tab) || consume(ctx, cmd_shift, Key::PageUp) {
            self.next_tab(-1);
        }
        if consume(ctx, cmd, Key::Tab) || consume(ctx, cmd, Key::PageDown) {
            self.next_tab(1);
        }

        if ctx.input_mut(|i| i.consume_key(Modifiers::default(), Key::Escape)) && self.search.open {
            self.search.open = false;
            self.search.query.clear();
            self.search.matches.clear();
        }
    }

    // ---- UI -------------------------------------------------------------

    fn top_bar(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        egui::Panel::top("shiori_top").show(ui, |ui| {
            egui::MenuBar::new().ui(ui, |ui| {
                ui.menu_button("ファイル", |ui| {
                    if ui.button("新規                 Ctrl+N").clicked() {
                        self.new_doc();
                        ui.close();
                    }
                    if ui.button("開く…                Ctrl+O").clicked() {
                        self.open_dialog();
                        ui.close();
                    }
                    ui.separator();
                    if ui.button("保存                 Ctrl+S").clicked() {
                        self.save_active();
                        ui.close();
                    }
                    if ui.button("名前を付けて保存…  Ctrl+Shift+S").clicked() {
                        self.save_as_active();
                        ui.close();
                    }
                    ui.separator();
                    if ui.button("タブを閉じる       Ctrl+W").clicked() {
                        let a = self.active;
                        self.request_close(a);
                        ui.close();
                    }
                    if ui.button("終了                 Ctrl+Q").clicked() {
                        self.request_quit(ctx);
                        ui.close();
                    }
                });

                ui.menu_button("表示", |ui| {
                    ui.checkbox(&mut self.preview, "Markdown プレビュー  Ctrl+P");
                    ui.checkbox(&mut self.settings.word_wrap, "折り返し");
                    ui.checkbox(&mut self.settings.show_line_numbers, "行番号");
                    ui.separator();
                    let dark = self.settings.theme == ThemeMode::Dark;
                    if ui.button(if dark { "テーマ: ダーク" } else { "テーマ: ライト" }).clicked() {
                        self.settings.theme = if dark {
                            ThemeMode::Light
                        } else {
                            ThemeMode::Dark
                        };
                    }
                    let sans = self.settings.font == FontChoice::Sans;
                    if ui
                        .button(if sans { "フォント: サンセリフ" } else { "フォント: 等幅" })
                        .clicked()
                    {
                        self.settings.font = if sans {
                            FontChoice::Mono
                        } else {
                            FontChoice::Sans
                        };
                    }
                    ui.separator();
                    if ui.button("拡大  Ctrl+=").clicked() {
                        self.settings.font_size_step(1.0);
                    }
                    if ui.button("縮小  Ctrl+-").clicked() {
                        self.settings.font_size_step(-1.0);
                    }
                    if ui.button("等倍  Ctrl+0").clicked() {
                        self.settings.font_size = 16.0;
                    }
                });

                ui.menu_button("栞", |ui| {
                    if ui.button("この行に栞を挟む/外す    Ctrl+B").clicked() {
                        self.toggle_bookmark_line();
                        ui.close();
                    }
                    let bookmarked = self
                        .docs
                        .get(self.active)
                        .map(|d| self.bookmarks.is_file_bookmarked(&d.key()))
                        .unwrap_or(false);
                    let label = if bookmarked {
                        "ファイル栞から外す  Ctrl+Shift+B"
                    } else {
                        "ファイル栞に追加    Ctrl+Shift+B"
                    };
                    if ui.button(label).clicked() {
                        self.toggle_file_bookmark();
                        ui.close();
                    }
                    ui.separator();
                    ui.checkbox(&mut self.show_bookmarks, "栞パネル  Ctrl+J");
                });

                ui.menu_button("検索", |ui| {
                    if ui.button("検索…  Ctrl+F").clicked() {
                        self.search.open = true;
                        self.search.focus = true;
                        ui.close();
                    }
                });
            });

            self.tab_bar(ui);

            if self.search.open {
                let mut jump = false;
                let mut close = false;
                ui.horizontal(|ui| {
                    ui.label("検索:");
                    let resp = ui.add(
                        egui::TextEdit::singleline(&mut self.search.query)
                            .hint_text("検索語")
                            .desired_width(220.0),
                    );
                    if self.search.focus {
                        let _ = resp.request_focus();
                        self.search.focus = false;
                        jump = true;
                    }
                    if resp.changed() {
                        self.search.current = 0;
                        jump = true;
                    }
                    let total = self.search.matches.len();
                    let cur = if total == 0 { 0 } else { self.search.current + 1 };
                    ui.label(format!("{cur}/{total}"));
                    if ui.button("前").clicked() {
                        self.search.prev();
                        jump = true;
                    }
                    if ui.button("次").clicked() {
                        self.search.next();
                        jump = true;
                    }
                    if ui.button("閉じる").clicked() {
                        close = true;
                    }
                    if resp.lost_focus() && ui.input(|i| i.key_pressed(Key::Enter)) {
                        self.search.next();
                        jump = true;
                    }
                });

                if close {
                    self.search.open = false;
                    self.search.query.clear();
                    self.search.matches.clear();
                } else if jump {
                    let Self {
                        docs,
                        search,
                        active,
                        ..
                    } = self;
                    if let Some(doc) = docs.get(*active) {
                        search.update(&doc.text);
                        if let Some(m) = search.current_match() {
                            let id = egui::Id::new(("shiori_editor", doc.uid));
                            let end = (m + search.query.len()).min(doc.text.len());
                            editor::select_byte_range(ctx, id, &doc.text, m, end);
                        }
                    }
                }
            }
        });
    }

    fn tab_bar(&mut self, ui: &mut egui::Ui) {
        let mut close: Option<usize> = None;
        let mut select: Option<usize> = None;
        let mut new = false;

        egui::ScrollArea::horizontal()
            .id_salt("shiori_tabs")
            .max_height(28.0)
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 4.0;
                    for i in 0..self.docs.len() {
                        let title = self.docs[i].title();
                        let dirty = self.docs[i].dirty;
                        let label = if dirty { format!("● {title}") } else { title };
                        let selected = i == self.active;
                        if ui.selectable_label(selected, label).clicked() {
                            select = Some(i);
                        }
                        if ui.small_button("✕").clicked() {
                            close = Some(i);
                        }
                        ui.separator();
                    }
                    if ui.button("＋").on_hover_text("新規タブ (Ctrl+N)").clicked() {
                        new = true;
                    }
                });
            });

        if let Some(i) = select {
            self.active = i;
        }
        if new {
            self.new_doc();
        }
        if let Some(i) = close {
            self.request_close(i);
        }
    }

    fn bookmark_panel(&mut self, ui: &mut egui::Ui) {
        if !self.show_bookmarks {
            return;
        }
        let active = self.active;
        let files = self.bookmarks.files.clone();
        let mut jump: Option<usize> = None;
        let mut open: Option<PathBuf> = None;
        let mut remove_key: Option<String> = None;

        egui::Panel::right("shiori_bookmark_panel")
            .default_size(250.0)
            .show(ui, |ui| {
                ui.add_space(4.0);
                ui.heading("栞");
                ui.separator();

                ui.label(RichText::new("このファイルの栞").strong());
                let mut any = false;
                if let Some(doc) = self.docs.get(active) {
                    for &line in &doc.line_bookmarks {
                        any = true;
                        let snippet: String =
                            util::line_text(&doc.text, line).chars().take(28).collect();
                        let label = format!("\u{25C6} {:>4}  {}", line + 1, snippet);
                        if ui.selectable_label(false, label).clicked() {
                            jump = Some(line);
                        }
                    }
                }
                if !any {
                    ui.weak("（Ctrl+B でこの行に栞）");
                }

                ui.add_space(8.0);
                ui.separator();
                ui.label(RichText::new("ファイル栞").strong());
                if files.is_empty() {
                    ui.weak("（Ctrl+Shift+B で追加）");
                }
                for f in &files {
                    ui.horizontal(|ui| {
                        if ui.selectable_label(false, &f.title).clicked() {
                            if let Some(p) = &f.path {
                                open = Some(p.clone());
                            }
                        }
                        ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                            if ui.small_button("✕").clicked() {
                                remove_key = Some(f.key.clone());
                            }
                        });
                    });
                    if let Some(p) = &f.path {
                        ui.weak(p.display().to_string());
                    }
                }
            });

        if let Some(line) = jump {
            self.pending_jump = Some(line);
        }
        if let Some(p) = open {
            self.open_path(p);
        }
        if let Some(key) = remove_key {
            self.bookmarks.files.retain(|f| f.key != key);
            self.bookmarks.save();
        }
    }

    fn central(&mut self, ui: &mut egui::Ui) {
        egui::CentralPanel::default().show(ui, |ui| {
            if self.docs.is_empty() {
                ui.centered_and_justified(|ui| {
                    ui.label("ファイルを開く（Ctrl+O）か、Ctrl+N で新規作成");
                });
                return;
            }

            if self.preview {
                let Self {
                    docs,
                    active,
                    md_cache,
                    ..
                } = self;
                if let Some(doc) = docs.get(*active) {
                    egui::ScrollArea::vertical()
                        .auto_shrink([false, false])
                        .show(ui, |ui| {
                            egui_commonmark::CommonMarkViewer::new().show(ui, md_cache, &doc.text);
                        });
                }
                return;
            }

            let Self {
                docs,
                active,
                settings,
                search,
                pending_jump,
                ..
            } = self;
            let Some(doc) = docs.get_mut(*active) else {
                return;
            };

            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    let out = editor::show(ui, doc, settings, search);
                    if out.changed {
                        doc.dirty = true;
                    }
                    doc.cursor_char = out.cursor_char;

                    if let Some(line) = pending_jump.take() {
                        let id = egui::Id::new(("shiori_editor", doc.uid));
                        let last = util::line_count(&doc.text).saturating_sub(1);
                        editor::jump_to_line(ui.ctx(), id, &doc.text, line.min(last));
                    }
                });
        });
    }

    fn dialogs(&mut self, ctx: &egui::Context) {
        if let Some(i) = self.confirm_close {
            let title = self.docs.get(i).map(|d| d.title()).unwrap_or_default();
            egui::Window::new("未保存の変更")
                .collapsible(false)
                .resizable(false)
                .anchor(Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label(format!("「{title}」を保存しますか？"));
                    ui.add_space(6.0);
                    ui.horizontal(|ui| {
                        if ui.button("保存").clicked() {
                            self.confirm_close = None;
                            let has_path =
                                self.docs.get(i).map(|d| d.path.is_some()).unwrap_or(false);
                            if has_path {
                                let _ = self.docs.get_mut(i).map(|d| d.save());
                                self.close_doc(i);
                            } else {
                                self.active = i;
                                self.save_as_active();
                                if self.docs.get(i).map(|d| !d.dirty).unwrap_or(false) {
                                    self.close_doc(i);
                                }
                            }
                        }
                        if ui.button("保存しない").clicked() {
                            self.confirm_close = None;
                            self.close_doc(i);
                        }
                        if ui.button("キャンセル").clicked() {
                            self.confirm_close = None;
                        }
                    });
                });
        }

        if self.confirm_quit {
            egui::Window::new("未保存の変更があります")
                .collapsible(false)
                .resizable(false)
                .anchor(Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label("保存していない変更があります。終了しますか？");
                    ui.add_space(6.0);
                    ui.horizontal(|ui| {
                        if ui.button("保存して終了").clicked() {
                            self.confirm_quit = false;
                            self.finish_quit(ctx, true);
                        }
                        if ui.button("保存せず終了").clicked() {
                            self.confirm_quit = false;
                            self.finish_quit(ctx, false);
                        }
                        if ui.button("キャンセル").clicked() {
                            self.confirm_quit = false;
                        }
                    });
                });
        }
    }

    fn status_bar(&mut self, ui: &mut egui::Ui) {
        egui::Panel::bottom("shiori_status").show(ui, |ui| {
            ui.horizontal(|ui| {
                if let Some(doc) = self.docs.get(self.active) {
                    let line = doc.cursor_line() + 1;
                    let byte = util::char_to_byte(&doc.text, doc.cursor_char);
                    let line_start = util::line_to_byte(&doc.text, line - 1);
                    let col = doc.text[line_start..byte.min(doc.text.len())].chars().count() + 1;
                    let md = if doc.is_markdown() { "  [Markdown]" } else { "" };
                    ui.label(format!("{}   行 {line}, 列 {col}{md}", doc.title()));
                    if let Some(p) = &doc.path {
                        ui.separator();
                        ui.weak(p.display().to_string());
                    }
                }
                ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                    if let Some(msg) = &self.status {
                        ui.label(RichText::new(msg).color(egui::Color32::from_rgb(150, 200, 150)));
                    }
                    ui.weak(format!(
                        "{}pt  {}",
                        self.settings.font_size as i32,
                        if self.preview { "プレビュー" } else { "編集" }
                    ));
                });
            });
        });
    }

    fn tick_autosave(&mut self, ctx: &egui::Context) {
        let t = ctx.input(|i| i.time);
        if t - self.last_autosave > 4.0 {
            self.last_autosave = t;
            self.save_state(true);
        }
    }
}

impl eframe::App for ShioriApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();

        self.poll_ipc();
        self.handle_close_request(&ctx);
        self.handle_shortcuts(&ctx);

        theme::apply(
            &ctx,
            self.settings.theme,
            self.settings.font,
            self.settings.font_size,
        );

        let title = self
            .docs
            .get(self.active)
            .map(|d| {
                if d.dirty {
                    format!("* {} — shiori", d.title())
                } else {
                    format!("{} — shiori", d.title())
                }
            })
            .unwrap_or_else(|| "shiori".into());
        if title != self.last_title {
            ctx.send_viewport_cmd(ViewportCommand::Title(title.clone()));
            self.last_title = title;
        }

        self.top_bar(ui, &ctx);
        self.refresh_search();
        self.status_bar(ui);
        self.bookmark_panel(ui);
        self.central(ui);
        self.dialogs(&ctx);
        self.tick_autosave(&ctx);
    }

    fn on_exit(&mut self) {
        if !self.skip_save_state {
            self.save_state(true);
        }
        ipc::cleanup();
    }
}
