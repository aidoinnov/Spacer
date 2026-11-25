#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]
mod automation;
mod backend;
mod document;
mod latest_work;
mod layout;
mod launch;
mod model;
mod motion;
mod navigation;
mod platform;
mod projection;
mod session_lifecycle;
mod ui;
mod watch;
mod wire;
use std::{borrow::Cow, path::PathBuf};
fn main() {
    #[cfg(not(feature = "qa"))]
    if std::env::args_os().any(|arg| arg.to_string_lossy().starts_with("--qa-")) {
        eprintln!("QA options require the qa feature");
        std::process::exit(64);
    }
    let launch_args: Vec<_> = std::env::args_os().skip(1).collect();
    if let Some(command) = launch::terminal(&launch_args) {
        match command {
            launch::Terminal::Help => print!("{}", launch::HELP),
            launch::Terminal::Version => println!("Spacer {}", env!("CARGO_PKG_VERSION")),
            launch::Terminal::Cli => {
                let code = platform::process::run_cli(&launch_args).unwrap_or_else(|error| {
                    eprintln!("Spacer CLI companion could not start: {error}");
                    1
                });
                std::process::exit(code);
            }
        }
        return;
    }
    #[cfg(not(feature = "qa"))]
    if let Err(error) = launch::validate_gui(&launch_args) {
        eprintln!("{error}");
        std::process::exit(64);
    }
    #[cfg(feature = "qa")]
    if std::env::args().nth(1).as_deref() == Some("--qa-wire-compare") {
        let args: Vec<_> = std::env::args().collect();
        let result = (|| -> anyhow::Result<_> {
            let json = model::Snapshot::load(std::path::Path::new(&args[2]))?;
            let binary = model::Snapshot::load(std::path::Path::new(&args[3]))?;
            anyhow::ensure!(
                json.root == binary.root
                    && json.files == binary.files
                    && json.folders == binary.folders
                    && json.errors == binary.errors
                    && json.excluded == binary.excluded
                    && json.cancelled == binary.cancelled
                    && json.tags == binary.tags
                    && json.issues == binary.issues
                    && json.volume_total == binary.volume_total
                    && json.volume_free == binary.volume_free
                    && json.is_volume_root == binary.is_volume_root
                    && json.volume_traversal == binary.volume_traversal,
                "JSON/binary header mismatch"
            );
            anyhow::ensure!(
                json.nodes == binary.nodes,
                "JSON/binary node semantics mismatch"
            );
            Ok(
                serde_json::json!({"passed":true,"nodes":json.nodes.len(),"jsonBytes":std::fs::metadata(&args[2])?.len(),"binaryBytes":std::fs::metadata(&args[3])?.len()}),
            )
        })();
        let report = match result {
            Ok(value) => value,
            Err(error) => serde_json::json!({"passed":false,"error":error.to_string()}),
        };
        std::fs::write(&args[4], serde_json::to_vec_pretty(&report).unwrap()).unwrap();
        return;
    }

    let mut args = std::env::args_os().skip(1);
    let mut initial = None;
    let mut qa_output = None;
    let mut progress_probe = None;
    let mut navigation_probe = None;
    let mut document_probe = None;
    let mut volume_probe = None;
    let mut scale_probe = None;
    let mut visible_probe = false;
    let mut json_wire = false;
    let mut background_qa = false;
    while let Some(arg) = args.next() {
        if arg == "--qa-background" {
            background_qa = true;
        } else if arg == "--qa-wire-json" {
            json_wire = true;
        } else if arg == "--qa-visible" {
            visible_probe = true;
        } else if arg == "--qa-scale-only" {
            scale_probe = args.next().map(PathBuf::from);
        } else if arg == "--qa-volumes-only" {
            volume_probe = args.next().map(PathBuf::from);
        } else if arg == "--qa-document-only" {
            document_probe = args.next().map(PathBuf::from);
        } else if arg == "--qa-navigation-only" {
            navigation_probe = args.next().map(PathBuf::from);
        } else if arg == "--qa-progress-only" {
            progress_probe = args.next().map(PathBuf::from);
        } else if arg == "--qa-output" {
            qa_output = args.next().map(PathBuf::from);
        } else if arg == "--scan" || arg == "--snapshot" {
            initial = args.next().map(PathBuf::from);
        } else {
            initial = Some(PathBuf::from(arg));
        }
    }
    #[cfg(not(feature = "qa"))]
    if progress_probe.is_some()
        || navigation_probe.is_some()
        || document_probe.is_some()
        || volume_probe.is_some()
        || scale_probe.is_some()
        || visible_probe
        || json_wire
    {
        eprintln!("--qa-progress-only requires the qa feature");
        std::process::exit(64);
    }
    let _ = json_wire;
    gpui_kit::application()
        .with_assets(gpui_kit::assets::AllAssets)
        .run(move |cx| {
            // GPUI only polls quit futures for 200 ms. Finish owned runtime
            // cleanup inside the callback before returning its ready future.
            cx.on_app_quit(|_| {
                if let Err(error) = session_lifecycle::finish_all() {
                    eprintln!("{error:#}");
                }
                async {}
            }).detach();
            gpui_kit::init(cx);
            ui::theme::init(cx);
            cx.text_system()
                .add_fonts(vec![
                    Cow::Borrowed(include_bytes!("../assets/fonts/NotoSansKR-Regular.ttf")),
                    Cow::Borrowed(include_bytes!("../assets/fonts/NotoSansKR-Medium.ttf")),
                    Cow::Borrowed(include_bytes!("../assets/fonts/NotoSansKR-SemiBold.ttf")),
                    Cow::Borrowed(include_bytes!("../assets/fonts/NotoSansKR-Bold.ttf")),
                ])
                .expect("load shared UI font");
            let probe = progress_probe.is_some()
                || navigation_probe.is_some()
                || document_probe.is_some()
                || volume_probe.is_some()
                || scale_probe.is_some();
            let handle = ui::windows::open_request(
                ui::windows::OpenRequest {
                    initial,
                    qa_output,
                    visible: (!probe || visible_probe) && !background_qa,
                    focus: !probe && !background_qa,
                },
                cx,
            )
            .expect("open GPUI window");
            #[cfg(feature = "qa")]
            if let Some(output) = scale_probe {
                ui::qa_scale::run(handle, output, cx);
                return;
            }
            #[cfg(feature = "qa")]
            if let Some(output) = volume_probe {
                ui::qa_volumes::run(handle, output, cx);
                return;
            }
            #[cfg(feature = "qa")]
            if let Some(output) = document_probe {
                ui::qa_documents::run(handle, output, cx);
                return;
            }
            #[cfg(feature = "qa")]
            if let Some(output) = navigation_probe {
                ui::qa_navigation::run(handle, output, cx);
                return;
            }
            #[cfg(feature = "qa")]
            if let Some(output) = progress_probe {
                ui::qa_progress::run(handle, output, cx);
                return;
            }
            #[cfg(not(feature = "qa"))]
            let _ = handle;
            ui::automation::install(cx);
            cx.on_window_closed(|cx, _| {
                if cx.windows().is_empty() {
                    cx.quit();
                }
            })
            .detach();
            if !background_qa {
                cx.activate(true);
            }
        });
}
