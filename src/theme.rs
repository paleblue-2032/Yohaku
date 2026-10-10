use std::collections::BTreeMap;

use egui::{Color32, CornerRadius, FontFamily, FontId, Stroke, TextStyle, Vec2};

use crate::settings::{Accent, FontChoice, ThemeMode};

fn tune_widgets(v: &mut egui::Visuals, accent: Color32, dark: bool) {
    let r = CornerRadius::same(6);
    v.widgets.noninteractive.corner_radius = r;
    v.widgets.inactive.corner_radius = r;
    v.widgets.hovered.corner_radius = r;
    v.widgets.active.corner_radius = r;
    v.widgets.open.corner_radius = r;

    if dark {
        let text = Color32::from_rgb(0xe8, 0xe8, 0xe8);
        let weak = Color32::from_rgb(0x9a, 0x9a, 0x9a);

        v.widgets.noninteractive.bg_fill = Color32::from_rgb(0x20, 0x20, 0x20);
        v.widgets.noninteractive.weak_bg_fill = Color32::from_rgb(0x20, 0x20, 0x20);
        v.widgets.noninteractive.bg_stroke = Stroke::new(1.0, Color32::from_rgb(0x33, 0x33, 0x33));
        v.widgets.noninteractive.fg_stroke = Stroke::new(1.0, weak);

        v.widgets.inactive.bg_fill = Color32::from_rgb(0x2a, 0x2a, 0x2a);
        v.widgets.inactive.weak_bg_fill = Color32::from_rgb(0x2a, 0x2a, 0x2a);
        v.widgets.inactive.bg_stroke = Stroke::NONE;
        v.widgets.inactive.fg_stroke = Stroke::new(1.0, text);

        v.widgets.hovered.bg_fill = Color32::from_rgb(0x33, 0x33, 0x33);
        v.widgets.hovered.weak_bg_fill = Color32::from_rgb(0x33, 0x33, 0x33);
        v.widgets.hovered.bg_stroke = Stroke::new(1.0, accent.gamma_multiply(0.5));
        v.widgets.hovered.fg_stroke = Stroke::new(1.0, Color32::WHITE);

        v.widgets.active.bg_fill = Color32::from_rgb(0x3a, 0x3a, 0x3a);
        v.widgets.active.weak_bg_fill = Color32::from_rgb(0x3a, 0x3a, 0x3a);
        v.widgets.active.bg_stroke = Stroke::new(1.0, accent);
        v.widgets.active.fg_stroke = Stroke::new(1.0, Color32::WHITE);

        v.widgets.open.bg_fill = Color32::from_rgb(0x33, 0x33, 0x33);
        v.widgets.open.weak_bg_fill = Color32::from_rgb(0x33, 0x33, 0x33);
        v.widgets.open.fg_stroke = Stroke::new(1.0, text);

        v.override_text_color = Some(text);
    } else {
        let text = Color32::from_rgb(0x1a, 0x1a, 0x1a);
        v.widgets.noninteractive.bg_stroke = Stroke::new(1.0, Color32::from_rgb(0xe2, 0xe2, 0xe2));
        v.widgets.inactive.bg_fill = Color32::from_rgb(0xe8, 0xe8, 0xe8);
        v.widgets.inactive.weak_bg_fill = Color32::from_rgb(0xec, 0xec, 0xec);
        v.widgets.hovered.bg_fill = Color32::from_rgb(0xdd, 0xdd, 0xdd);
        v.widgets.hovered.weak_bg_fill = Color32::from_rgb(0xe3, 0xe3, 0xe3);
        v.widgets.hovered.bg_stroke = Stroke::new(1.0, accent.gamma_multiply(0.7));
        v.widgets.active.bg_stroke = Stroke::new(1.0, accent);
        v.override_text_color = Some(text);
    }
}

pub fn apply(
    ctx: &egui::Context,
    mode: ThemeMode,
    accent: Accent,
    font: FontChoice,
    font_size: f32,
) {
    let a = accent.color();

    let mut dark = egui::Visuals::dark();
    dark.panel_fill = Color32::from_rgb(0x20, 0x20, 0x20);
    dark.window_fill = Color32::from_rgb(0x26, 0x26, 0x26);
    dark.extreme_bg_color = Color32::from_rgb(0x1b, 0x1b, 0x1b);
    dark.faint_bg_color = Color32::from_rgb(0x2b, 0x2b, 0x2b);
    dark.window_corner_radius = CornerRadius::same(10);
    dark.menu_corner_radius = CornerRadius::same(8);
    dark.selection = egui::style::Selection {
        bg_fill: Color32::from_rgba_unmultiplied(a.r(), a.g(), a.b(), 130),
        stroke: Stroke::new(1.0, a),
    };
    dark.hyperlink_color = a;
    tune_widgets(&mut dark, a, true);

    let mut light = egui::Visuals::light();
    light.panel_fill = Color32::from_rgb(0xf3, 0xf3, 0xf3);
    light.window_fill = Color32::from_rgb(0xff, 0xff, 0xff);
    light.extreme_bg_color = Color32::from_rgb(0xff, 0xff, 0xff);
    light.faint_bg_color = Color32::from_rgb(0xec, 0xec, 0xec);
    light.window_corner_radius = CornerRadius::same(10);
    light.menu_corner_radius = CornerRadius::same(8);
    light.selection = egui::style::Selection {
        bg_fill: Color32::from_rgba_unmultiplied(a.r(), a.g(), a.b(), 100),
        stroke: Stroke::new(1.0, a),
    };
    light.hyperlink_color = a;
    tune_widgets(&mut light, a, false);

    ctx.set_visuals_of(egui::Theme::Dark, dark);
    ctx.set_visuals_of(egui::Theme::Light, light);
    ctx.set_theme(match mode {
        ThemeMode::Dark => egui::ThemePreference::Dark,
        ThemeMode::Light => egui::ThemePreference::Light,
        ThemeMode::System => egui::ThemePreference::System,
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
        style.spacing.item_spacing = Vec2::new(8.0, 6.0);
        style.spacing.button_padding = Vec2::new(11.0, 5.0);
        style.spacing.menu_margin = egui::Margin::same(6);
        style.spacing.interact_size.y = 22.0;
    });
}
