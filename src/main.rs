mod app;
mod bookmarks;
mod document;
mod editor;
mod fonts;
mod i18n;
mod ipc;
mod search;
mod session;
mod settings;
mod theme;
mod util;

use std::path::PathBuf;

fn parse_args() -> (Vec<PathBuf>, bool) {
    let mut files = Vec::new();
    let mut force_new = false;
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "-h" | "--help" => {
                print!("{}", i18n::get(settings::Settings::load().lang).help);
                std::process::exit(0);
            }
            "-V" | "--version" => {
                println!("shiori {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            "-n" | "--new" => force_new = true,
            s if s.starts_with('-') && s != "-" => {
                eprintln!("unknown option: {s}");
                eprintln!("see `shiori --help`");
                std::process::exit(2);
            }
            s => files.push(PathBuf::from(s)),
        }
    }
    (files, force_new)
}

fn main() -> eframe::Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();

    let (files, force_new) = parse_args();

    // すでに起動していれば、既存ウィンドウにファイルを渡して終了する。
    if !force_new && !files.is_empty() && ipc::send_to_existing(&files) {
        return Ok(());
    }

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("shiori")
            .with_app_id("shiori")
            .with_inner_size([940.0, 700.0])
            .with_min_inner_size([460.0, 320.0]),
        ..Default::default()
    };

    eframe::run_native(
        "shiori",
        options,
        Box::new(move |cc| {
            fonts::install(&cc.egui_ctx);
            let rx = ipc::start_listener(cc.egui_ctx.clone());
            Ok(Box::new(app::ShioriApp::new(cc, files, force_new, rx)))
        }),
    )
}
