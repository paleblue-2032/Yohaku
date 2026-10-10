use std::collections::BTreeMap;

use egui::{Color32, FontFamily, FontId, TextStyle};

use crate::settings::{FontChoice, ThemeMode};

pub fn apply(ctx: &egui::Context, mode: ThemeMode, font: FontChoice, font_size: f32) {
    let mut dark = egui::Visuals::dark();
    dark.panel_fill = Color32::from_gray(18);
    dark.extreme_bg_color = Color32::from_gray(12);

    let mut light = egui::Visuals::light();
    light.panel_fill = Color32::from_gray(250);

    ctx.set_visuals_of(egui::Theme::Dark, dark);
    ctx.set_visuals_of(egui::Theme::Light, light);
    ctx.set_theme(match mode {
        ThemeMode::Dark => egui::ThemePreference::Dark,
        ThemeMode::Light => egui::ThemePreference::Light,
    });

    let family = match font {
        FontChoice::Sans => FontFamily::Proportional,
        FontChoice::Mono => FontFamily::Monospace,
    };
    let styles: BTreeMap<TextStyle, FontId> = [
        (TextStyle::Body, FontId::new(font_size, family.clone())),
        (TextStyle::Button, FontId::new(font_size, family.clone())),
        (
            TextStyle::Small,
            FontId::new((font_size - 2.0).max(8.0), family.clone()),
        ),
        (
            TextStyle::Heading,
            FontId::new(font_size + 4.0, FontFamily::Proportional),
        ),
        (
            TextStyle::Monospace,
            FontId::new(font_size, FontFamily::Monospace),
        ),
    ]
    .into();

    ctx.all_styles_mut(|style| {
        style.text_styles = styles.clone();
    });
}
