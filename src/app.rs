use std::path::PathBuf;
use std::sync::mpsc::Receiver;
use std::time::{SystemTime, UNIX_EPOCH};

use egui::{Align, Align2, Key, Modifiers, RichText, ViewportCommand};

use crate::bookmarks::BookmarkStore;
use crate::document::Document;
use crate::editor;
use crate::i18n::{self, Lang};
use crate::ipc;
use crate::search::SearchState;
use crate::session::{self, Session, TabState};
use crate::settings::{Accent, FontChoice, Settings, ThemeMode};
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
    focus_editor: bool,
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
            settings.accent,
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
            focus_editor: true,
            last_autosave: 0.0,
            skip_save_state: false,
            last_title: String::new(),
        };

        if !files.is_empty() {
            for f in files {
                app.open_path(f);
            }
        } else {
            // 単独起動は「新しいタブ」で開始する（前回のタブは後ろに復元）。
            if !force_new {
                app.restore_session();
            }
            app.new_doc();
        }
        if app.docs.is_empty() {
            app.new_doc();
        }
        app
    }

    fn s(&self) -> &'static i18n::S {
        i18n::get(self.settings.lang)
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
        self.focus_editor = true;
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
            self.focus_editor = true;
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
                self.focus_editor = true;
            }
            Err(e) => {
                let msg = self
                    .s()
                    .open_failed
                    .replace("{}", &format!("{}", path.display()));
                self.set_status(format!("{msg} ({e})"));
            }
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
        self.focus_editor = true;
    }

    fn save_active(&mut self) {
        let a = self.active;
        let has_path = self.docs.get(a).map(|d| d.path.is_some()).unwrap_or(false);
        if !has_path {
            self.save_as_active();
            return;
        }
        let res = self.docs.get_mut(a).map(|d| d.save());
        let saved = self.s().saved.to_string();
        match res {
            Some(Ok(())) => self.set_status(saved),
            Some(Err(e)) => {
                let msg = self.s().save_failed.replace("{}", &e.to_string());
                self.set_status(msg);
            }
            None => {}
        }
    }

    fn save_as_active(&mut self) {
        let a = self.active;
        let name = self
            .docs
            .get(a)
            .map(|d| d.file_name())
            .unwrap_or_else(|| "untitled.txt".into());
        let dialog = rfd::FileDialog::new()
            .set_title(self.s().save_as)
            .set_file_name(name);
        if let Some(p) = dialog.save_file() {
            let res = self.docs.get_mut(a).map(|d| d.save_as(p));
            let saved = self.s().saved.to_string();
            match res {
                Some(Ok(())) => self.set_status(saved),
                Some(Err(e)) => {
                    let msg = self.s().save_failed.replace("{}", &e.to_string());
                    self.set_status(msg);
                }
                None => {}
            }
        }
    }

    fn open_dialog(&mut self) {
        if let Some(paths) = rfd::FileDialog::new().set_title(self.s().open).pick_files() {
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
            let msg = if on { self.s().bm_added } else { self.s().bm_removed };
            self.set_status(msg.to_string());
        }
    }

    fn toggle_file_bookmark(&mut self) {
        let a = self.active;
        let info = self
            .docs
            .get(a)
            .map(|d| (d.key(), d.display_title(self.s().untitled), d.path.clone(), d.untitled_id.clone()));
        if let Some((key, title, path, uid)) = info {
            let added = self.bookmarks.toggle_file(key, title, path, uid);
            self.bookmarks.save();
            let msg = if added { self.s().fbm_added } else { self.s().fbm_removed };
            self.set_status(msg.to_string());
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

        // 空の無題タブはセッションに残さない（起動のたびに増えないように）。
        let tabs: Vec<TabState> = self
            .docs
            .iter()
            .filter(|d| d.path.is_some() || d.dirty || !d.text.is_empty())
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
        let lang = self.settings.lang;
        let s = i18n::get(lang);

        egui::Panel::top("shiori_top").show(ui, |ui| {
            egui::MenuBar::new().ui(ui, |ui| {
                ui.menu_button(s.file, |ui| {
                    if ui
                        .add(egui::Button::new(s.new).shortcut_text("Ctrl+N"))
                        .clicked()
                    {
                        self.new_doc();
                        ui.close();
                    }
                    if ui
                        .add(egui::Button::new(s.open).shortcut_text("Ctrl+O"))
                        .clicked()
                    {
                        self.open_dialog();
                        ui.close();
                    }
                    ui.separator();
                    if ui
                        .add(egui::Button::new(s.save).shortcut_text("Ctrl+S"))
                        .clicked()
                    {
                        self.save_active();
                        ui.close();
                    }
                    if ui
                        .add(egui::Button::new(s.save_as).shortcut_text("Ctrl+Shift+S"))
                        .clicked()
                    {
                        self.save_as_active();
                        ui.close();
                    }
                    ui.separator();
                    if ui
                        .add(egui::Button::new(s.close_tab).shortcut_text("Ctrl+W"))
                        .clicked()
                    {
                        let a = self.active;
                        self.request_close(a);
                        ui.close();
                    }
                    if ui
                        .add(egui::Button::new(s.quit).shortcut_text("Ctrl+Q"))
                        .clicked()
                    {
                        self.request_quit(ctx);
                        ui.close();
                    }
                });

                ui.menu_button(s.view, |ui| {
                    ui.checkbox(&mut self.preview, format!("{}  Ctrl+P", s.preview));
                    ui.checkbox(&mut self.settings.word_wrap, s.word_wrap);
                    ui.checkbox(&mut self.settings.show_line_numbers, s.line_numbers);
                    ui.separator();
                    if ui.button(format!("{}  Ctrl+=", s.zoom_in)).clicked() {
                        self.settings.font_size_step(1.0);
                    }
                    if ui.button(format!("{}  Ctrl+-", s.zoom_out)).clicked() {
                        self.settings.font_size_step(-1.0);
                    }
                    if ui.button(format!("{}  Ctrl+0", s.zoom_reset)).clicked() {
                        self.settings.font_size = 16.0;
                    }
                });

                ui.menu_button(s.bookmarks, |ui| {
                    if ui
                        .add(egui::Button::new(s.bookmark_line).shortcut_text("Ctrl+B"))
                        .clicked()
                    {
                        self.toggle_bookmark_line();
                        ui.close();
                    }
                    let bookmarked = self
                        .docs
                        .get(self.active)
                        .map(|d| self.bookmarks.is_file_bookmarked(&d.key()))
                        .unwrap_or(false);
                    let label = if bookmarked {
                        s.bookmark_file_remove
                    } else {
                        s.bookmark_file_add
                    };
                    if ui
                        .add(egui::Button::new(label).shortcut_text("Ctrl+Shift+B"))
                        .clicked()
                    {
                        self.toggle_file_bookmark();
                        ui.close();
                    }
                    ui.separator();
                    ui.checkbox(&mut self.show_bookmarks, format!("{}  Ctrl+J", s.bookmark_panel));
                });

                ui.menu_button(s.search, |ui| {
                    if ui
                        .add(egui::Button::new(s.find).shortcut_text("Ctrl+F"))
                        .clicked()
                    {
                        self.search.open = true;
                        self.search.focus = true;
                        ui.close();
                    }
                });

                ui.menu_button(s.settings, |ui| {
                    ui.label(RichText::new(s.theme).weak());
                    ui.radio_value(&mut self.settings.theme, ThemeMode::Dark, s.dark);
                    ui.radio_value(&mut self.settings.theme, ThemeMode::Light, s.light);
                    ui.radio_value(&mut self.settings.theme, ThemeMode::System, s.system);
                    ui.separator();
                    ui.label(RichText::new(s.accent).weak());
                    for a in Accent::ALL {
                        ui.radio_value(&mut self.settings.accent, a, a.name());
                    }
                    ui.separator();
                    ui.label(RichText::new(s.font).weak());
                    ui.radio_value(&mut self.settings.font, FontChoice::Sans, s.sans);
                    ui.radio_value(&mut self.settings.font, FontChoice::Mono, s.mono);
                    ui.separator();
                    ui.label(RichText::new(s.language).weak());
                    ui.radio_value(&mut self.settings.lang, Lang::En, s.english);
                    ui.radio_value(&mut self.settings.lang, Lang::Ja, s.japanese);
                });
            });

            self.tab_bar(ui, s);

            if self.search.open {
                let mut jump = false;
                let mut close = false;
                ui.horizontal(|ui| {
                    ui.label(s.find_hint);
                    let resp = ui.add(
                        egui::TextEdit::singleline(&mut self.search.query)
                            .hint_text(s.find_hint)
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
                    ui.label(RichText::new(format!("{cur}/{total}")).weak());
                    if ui.button(s.prev).clicked() {
                        self.search.prev();
                        jump = true;
                    }
                    if ui.button(s.next).clicked() {
                        self.search.next();
                        jump = true;
                    }
                    if ui.button(s.close).clicked() {
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

    fn tab_bar(&mut self, ui: &mut egui::Ui, s: &'static i18n::S) {
        let mut close: Option<usize> = None;
        let mut select: Option<usize> = None;
        let mut new = false;

        egui::ScrollArea::horizontal()
            .id_salt("shiori_tabs")
            .max_height(30.0)
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 6.0;
                    ui.add_space(2.0);
                    for i in 0..self.docs.len() {
                        let title = self.docs[i].display_title(s.untitled);
                        let dirty = self.docs[i].dirty;
                        let selected = i == self.active;
                        let text = if dirty {
                            format!("● {title}")
                        } else {
                            title
                        };
                        if ui.selectable_label(selected, text).clicked() {
                            select = Some(i);
                        }
                        // 閉じるボタンは選択タブにだけ出す（すっきり見せる）
                        if selected && ui.small_button("×").clicked() {
                            close = Some(i);
                        }
                    }
                    if ui.button("+").on_hover_text(s.new_tab_hint).clicked() {
                        new = true;
                    }
                });
            });

        if let Some(i) = select {
            self.active = i;
            self.focus_editor = true;
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
        let s = self.s();
        let active = self.active;
        let files = self.bookmarks.files.clone();
        let mut jump: Option<usize> = None;
        let mut open: Option<PathBuf> = None;
        let mut remove_key: Option<String> = None;

        egui::Panel::right("shiori_bookmark_panel")
            .default_size(250.0)
            .show(ui, |ui| {
                ui.add_space(6.0);
                ui.add_space(2.0);
                ui.label(RichText::new(s.this_file_bookmarks).strong());
                let mut any = false;
                if let Some(doc) = self.docs.get(active) {
                    for &line in &doc.line_bookmarks {
                        any = true;
                        let snippet: String =
                            util::line_text(&doc.text, line).chars().take(26).collect();
                        let label = format!("{:>4}   {}", line + 1, snippet);
                        if ui.selectable_label(false, label).clicked() {
                            jump = Some(line);
                        }
                    }
                }
                if !any {
                    ui.weak(s.no_line_bookmarks);
                }

                ui.add_space(10.0);
                ui.separator();
                ui.label(RichText::new(s.file_bookmarks).strong());
                if files.is_empty() {
                    ui.weak(s.no_file_bookmarks);
                }
                for f in &files {
                    ui.horizontal(|ui| {
                        if ui.selectable_label(false, &f.title).clicked() {
                            if let Some(p) = &f.path {
                                open = Some(p.clone());
                            }
                        }
                        ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                            if ui.small_button("×").clicked() {
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
        let s = self.s();
        let accent = self.settings.accent.color();

        egui::CentralPanel::default().show(ui, |ui| {
            if self.docs.is_empty() {
                ui.centered_and_justified(|ui| {
                    ui.label(s.empty_hint);
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

            let focus = self.focus_editor;
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
                    let out = editor::show(ui, doc, settings, search, accent);
                    if out.changed {
                        doc.dirty = true;
                    }
                    doc.cursor_char = out.cursor_char;

                    let id = egui::Id::new(("shiori_editor", doc.uid));
                    if focus {
                        ui.ctx().memory_mut(|m| m.request_focus(id));
                    }

                    if let Some(line) = pending_jump.take() {
                        let last = util::line_count(&doc.text).saturating_sub(1);
                        editor::jump_to_line(ui.ctx(), id, &doc.text, line.min(last));
                    }
                });
        });

        if self.focus_editor {
            self.focus_editor = false;
        }
    }

    fn dialogs(&mut self, ctx: &egui::Context) {
        let s = self.s();

        if let Some(i) = self.confirm_close {
            let title = self
                .docs
                .get(i)
                .map(|d| d.display_title(s.untitled))
                .unwrap_or_default();
            egui::Window::new(s.unsaved_title)
                .collapsible(false)
                .resizable(false)
                .anchor(Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label(s.unsaved_body.replace("{}", &title));
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        if ui.button(s.save).clicked() {
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
                        if ui.button(s.dont_save).clicked() {
                            self.confirm_close = None;
                            self.close_doc(i);
                        }
                        if ui.button(s.cancel).clicked() {
                            self.confirm_close = None;
                        }
                    });
                });
        }

        if self.confirm_quit {
            egui::Window::new(s.quit_title)
                .collapsible(false)
                .resizable(false)
                .anchor(Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label(s.quit_body);
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        if ui.button(s.save_and_quit).clicked() {
                            self.confirm_quit = false;
                            self.finish_quit(ctx, true);
                        }
                        if ui.button(s.quit_without_saving).clicked() {
                            self.confirm_quit = false;
                            self.finish_quit(ctx, false);
                        }
                        if ui.button(s.cancel).clicked() {
                            self.confirm_quit = false;
                        }
                    });
                });
        }
    }

    fn status_bar(&mut self, ui: &mut egui::Ui) {
        let s = self.s();
        egui::Panel::bottom("shiori_status").show(ui, |ui| {
            ui.horizontal(|ui| {
                if let Some(doc) = self.docs.get(self.active) {
                    let title = doc.display_title(s.untitled);
                    let line = doc.cursor_line() + 1;
                    let byte = util::char_to_byte(&doc.text, doc.cursor_char);
                    let line_start = util::line_to_byte(&doc.text, line - 1);
                    let col = doc.text[line_start..byte.min(doc.text.len())].chars().count() + 1;
                    let md = if doc.is_markdown() { "  ·  Markdown" } else { "" };
                    ui.label(format!("{title}    {} {line}, {} {col}{md}", s.line, s.col));
                }
                ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                    if let Some(msg) = &self.status {
                        ui.label(RichText::new(msg).color(self.settings.accent.color()));
                    }
                    let mode = if self.preview { s.preview_mode } else { s.edit };
                    ui.weak(format!("{}pt   {mode}", self.settings.font_size as i32));
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
            self.settings.accent,
            self.settings.font,
            self.settings.font_size,
        );

        let s = self.s();
        let title = self
            .docs
            .get(self.active)
            .map(|d| {
                let t = d.display_title(s.untitled);
                if d.dirty {
                    format!("● {} — {}", t, s.title)
                } else {
                    format!("{} — {}", t, s.title)
                }
            })
            .unwrap_or_else(|| s.title.to_string());
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

    fn clear_color(&self, visuals: &egui::Visuals) -> [f32; 4] {
        // 既定は半透明で壁紙が透けるため、不透明にする。
        visuals.panel_fill.to_normalized_gamma_f32()
    }

    fn on_exit(&mut self) {
        if !self.skip_save_state {
            self.save_state(true);
        }
        ipc::cleanup();
    }
}
