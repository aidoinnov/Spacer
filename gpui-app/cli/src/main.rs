//! Console host for the same native engine/document protocol as GPUI.
#[allow(dead_code)] // Canonical transport APIs also serve the GUI host.
#[path = "../../src/backend.rs"]
mod backend;
#[allow(dead_code)]
#[path = "../../src/document.rs"]
mod document;
#[allow(dead_code)]
#[path = "../../src/model.rs"]
mod model;
mod platform {
    pub(crate) use crate::process;
}
mod options;
#[path = "../../src/platform/paths.rs"]
mod paths;
#[allow(dead_code)]
#[path = "../../src/platform/process.rs"]
pub(crate) mod process;
mod run;
#[path = "../../src/session_lifecycle.rs"]
mod session_lifecycle;
#[allow(dead_code)]
#[path = "../../src/wire.rs"]
mod wire;

fn main() {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.iter().any(|a| a == "--help" || a == "-h") {
        print!("{}", options::HELP);
        return;
    }
    if args.iter().any(|a| a == "--version") {
        println!("Spacer CLI {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    let mut result = options::Options::parse(args).and_then(run::execute);
    if let Err(error) = session_lifecycle::finish_all() {
        eprintln!("{error:#}");
        if result.is_ok() {
            result = Err(error);
        }
    }
    match result {
        Ok((value, code)) => {
            println!("{}", value);
            std::process::exit(code);
        }
        Err(error) => {
            eprintln!("Spacer: {error:#}");
            std::process::exit(if error.is::<run::Cancelled>() { 130 } else { 1 });
        }
    }
}
