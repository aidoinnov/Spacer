//! Terminal-only responses must finish before creating a GPUI application.
use std::ffi::OsString;

#[cfg(any(not(feature = "qa"), test))]
pub fn validate_gui(args: &[OsString]) -> Result<(), &'static str> {
    let mut input = args.to_vec();
    if let Some(index) = input.iter().position(|arg| arg == "--background") {
        input.remove(index);
    }
    match input.as_slice() {
        [] => Ok(()),
        [path] if !path.is_empty() && !path.to_string_lossy().starts_with('-') => Ok(()),
        [flag, path]
            if (flag == "--scan" || flag == "--snapshot")
                && !path.is_empty()
                && !path.to_string_lossy().starts_with("--") =>
        {
            Ok(())
        }
        _ => Err("Use one PATH, --scan PATH, or --snapshot FILE. Use --cli for headless options."),
    }
}

pub const HELP: &str = "Spacer — disk usage analyzer\n\
Usage: Spacer [--background] [--scan PATH | --snapshot FILE | PATH]\n\
       Spacer --help\n\
       Spacer --version\n\n\
Use --cli --scan PATH or --cli --load FILE for headless operation.\n\
Use --background to open a window without activating the app.\n\
Use --cli --help for all headless options. Windows terminals can also run SpacerCLI.exe directly.\n\
MCP control is provided by scripts/mcp/space_sniffer_mcp.py.\n";

#[derive(Debug, PartialEq)]
pub enum Terminal {
    Help,
    Version,
    Cli,
}

pub fn terminal(args: &[OsString]) -> Option<Terminal> {
    if args.iter().any(|arg| arg == "--cli") {
        Some(Terminal::Cli)
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
            (vec!["--cli", "--scan", "/tmp"], Some(Terminal::Cli)),
            (vec!["--scan", "/tmp"], None),
        ] {
            assert_eq!(
                terminal(&args.into_iter().map(OsString::from).collect::<Vec<_>>()),
                expected
            );
        }
    }
    #[test]
    fn gui_arguments_are_not_silently_ignored() {
        for args in [
            vec!["--scan"],
            vec!["--wat"],
            vec!["--scan", "--snapshot"],
            vec!["a", "b"],
        ] {
            assert!(validate_gui(&args.into_iter().map(Into::into).collect::<Vec<_>>()).is_err());
        }
        assert!(validate_gui(&["--snapshot".into(), "a.sns".into()]).is_ok());
        assert!(validate_gui(&[]).is_ok());
        assert!(validate_gui(&["--background".into()]).is_ok());
        assert!(validate_gui(&["--background".into(), "--scan".into(), "/tmp".into()]).is_ok());
        assert!(validate_gui(&["--background".into(), "--background".into()]).is_err());
    }
}
