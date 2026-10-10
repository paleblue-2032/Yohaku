use std::sync::Arc;

use egui::{FontData, FontDefinitions, FontFamily};

/// 同梱した Noto Sans JP を egui に登録する。
/// Proportional の先頭に置き、Monospace にはフォールバックとして追加する。
pub fn install(ctx: &egui::Context) {
    let mut fonts = FontDefinitions::default();

    fonts.font_data.insert(
        "noto_sans_jp".to_owned(),
        Arc::new(FontData::from_static(include_bytes!(
            "../assets/fonts/NotoSansJP-VF.ttf"
        ))),
    );

    fonts
        .families
        .entry(FontFamily::Proportional)
        .or_default()
        .insert(0, "noto_sans_jp".to_owned());

    // 等幅フォントはラテンを egui 既定のまま使い、日本語だけ Noto にフォールバックさせる。
    fonts
        .families
        .entry(FontFamily::Monospace)
        .or_default()
        .push("noto_sans_jp".to_owned());

    ctx.set_fonts(fonts);
}
