//! Build-time platform composition; runtime UI contains no OS branches.
fn main() {
    println!("cargo:rerun-if-changed=product.json");
    let product: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string("product.json").unwrap()).unwrap();
    let name = product["name"].as_str().unwrap();
    let version = product["version"].as_str().unwrap();
    assert_eq!(version, std::env::var("CARGO_PKG_VERSION").unwrap());
    println!("cargo:rustc-env=SPACER_PRODUCT_NAME={name}");
    for file in ["app.rc", "AppIcon.ico"] {
        println!("cargo:rerun-if-changed=native/windows-app/{file}");
    }
    println!("cargo:rerun-if-env-changed=SPACE_SNIFFER_BUNDLE_ID");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let output = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap())
            .join("space-sniffer.res");
        let resource =
            std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap()).join("product.rc");
        let template = std::fs::read_to_string("native/windows-app/app.rc").unwrap();
        std::fs::write(
            &resource,
            template
                .replace("@NAME@", name)
                .replace(
                    "@VERSION_COMMAS@",
                    &format!("{},0", version.replace('.', ",")),
                )
                .replace("@VERSION@", version)
                .replace("@EXE@", product["executable"].as_str().unwrap()),
        )
        .unwrap();
        let result = std::process::Command::new("rc.exe")
            .current_dir("native/windows-app")
            .arg("/nologo")
            .arg(format!("/fo{}", output.display()))
            .arg(resource)
            .status()
            .expect("Windows SDK rc.exe is required");
        assert!(
            result.success(),
            "Windows application resource build failed"
        );
        println!("cargo:rustc-link-arg={}", output.display());
    }
}
