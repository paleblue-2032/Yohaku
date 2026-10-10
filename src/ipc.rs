//! 単一インスタンス IPC。
//!
//! すでに shiori が起動していれば、Unix ドメインソケット経由で開くファイルを
//! 送りつけて即終了する（=`shiori file` が既存ウィンドウのタブになる）。
//! Unix 以外では何もせず、新規ウィンドウを起動する。

use std::path::PathBuf;
use std::sync::mpsc::Receiver;

#[cfg(unix)]
fn socket_path() -> PathBuf {
    let base = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(crate::util::state_dir);
    base.join("shiori.sock")
}

/// 既存インスタンスへパスを送る。送れたら true。
#[cfg(unix)]
pub fn send_to_existing(paths: &[PathBuf]) -> bool {
    use std::io::Write;
    use std::os::unix::net::UnixStream;

    if paths.is_empty() {
        return false;
    }
    match UnixStream::connect(socket_path()) {
        Ok(mut stream) => {
            let msg = paths
                .iter()
                .map(|p| p.to_string_lossy().to_string())
                .collect::<Vec<_>>()
                .join("\n");
            let _ = stream.write_all(msg.as_bytes());
            true
        }
        Err(_) => false,
    }
}

#[cfg(not(unix))]
pub fn send_to_existing(_paths: &[PathBuf]) -> bool {
    false
}

/// 受信用のリスナを起動し、受け取ったパスを流すレシーバを返す。
#[cfg(unix)]
pub fn start_listener(ctx: egui::Context) -> Receiver<Vec<PathBuf>> {
    use std::io::Read;
    use std::os::unix::net::UnixListener;

    let (tx, rx) = std::sync::mpsc::channel();
    let sock = socket_path();
    let _ = std::fs::remove_file(&sock);

    match UnixListener::bind(&sock) {
        Ok(listener) => {
            std::thread::spawn(move || {
                for stream in listener.incoming() {
                    let Ok(mut stream) = stream else { continue };
                    let mut buf = String::new();
                    let _ = stream.read_to_string(&mut buf);
                    let paths: Vec<PathBuf> = buf
                        .lines()
                        .filter(|l| !l.trim().is_empty())
                        .map(PathBuf::from)
                        .collect();
                    if !paths.is_empty() {
                        let _ = tx.send(paths);
                        ctx.request_repaint();
                    }
                }
            });
        }
        Err(e) => log::warn!("IPC リスナの起動に失敗: {e}"),
    }

    rx
}

#[cfg(not(unix))]
pub fn start_listener(_ctx: egui::Context) -> Receiver<Vec<PathBuf>> {
    let (_tx, rx) = std::sync::mpsc::channel();
    rx
}

/// 終了時にソケットを片付ける。
#[cfg(unix)]
pub fn cleanup() {
    let _ = std::fs::remove_file(socket_path());
}

#[cfg(not(unix))]
pub fn cleanup() {}
