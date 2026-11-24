//! Build-time platform composition; runtime UI contains no OS branches.
fn main() {
    for file in ["app.rc", "AppIcon.ico"] {
        println!("cargo:rerun-if-changed=native/windows-app/{file}");
    }
    println!("cargo:rerun-if-env-changed=SPACE_SNIFFER_BUNDLE_ID");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let output = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap())
            .join("space-sniffer.res");
        let result = std::process::Command::new("rc.exe")
            .current_dir("native/windows-app")
            .arg("/nologo")
            .arg(format!("/fo{}", output.display()))
            .arg("app.rc")
            .status()
            .expect("Windows SDK rc.exe is required");
        assert!(
            result.success(),
            "Windows application resource build failed"
        );
        println!("cargo:rustc-link-arg={}", output.display());
    }
}
