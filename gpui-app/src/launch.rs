//! Terminal-only responses must finish before creating a GPUI application.
use std::ffi::OsString;

pub const HELP: &str = "Spacer — disk usage analyzer\n\
Usage: MacSpaceSniffer [--scan PATH | --snapshot FILE | PATH]\n\
       MacSpaceSniffer --help\n\
       MacSpaceSniffer --version\n\n\
This executable opens the GPUI desktop app. The 0.3.0 GPUI package does not\n\
include the legacy headless --cli interface. See docs/CLI_MCP_VALIDATION.md.\n\
MCP control is provided by scripts/mcp/space_sniffer_mcp.py.\n";

#[derive(Debug, PartialEq)]
pub enum Terminal {
    Help,
    Version,
    UnsupportedCli,
}

pub fn terminal(args: &[OsString]) -> Option<Terminal> {
    if args.iter().any(|arg| arg == "--cli") {
        Some(Terminal::UnsupportedCli)
    } else if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        Some(Terminal::Help)
    } else if args.iter().any(|arg| arg == "--version") {
        Some(Terminal::Version)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn terminal_options_do_not_become_scan_paths() {
        for (args, expected) in [
            (vec!["--help"], Some(Terminal::Help)),
            (vec!["-h"], Some(Terminal::Help)),
            (vec!["--version"], Some(Terminal::Version)),
            (vec!["--cli", "--scan", "/tmp"], Some(Terminal::UnsupportedCli)),
            (vec!["--scan", "/tmp"], None),
        ] {
            assert_eq!(terminal(&args.into_iter().map(OsString::from).collect::<Vec<_>>()), expected);
        }
    }
}
