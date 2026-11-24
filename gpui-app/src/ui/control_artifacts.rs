//! Export, inspection, and import job creation; no window registry or socket code.
use super::{
    app::Explorer,
    automation::required_path,
    control_jobs::{ImportResult, ImportStart, Jobs, Outcome, import_native},
};
use gpui_kit::*;
use serde_json::{Value, json};
pub(super) fn execute(
    command: &str,
    args: &Value,
    jobs: &mut Jobs,
    app: &mut Explorer,
    cx: &mut Context<Explorer>,
) -> anyhow::Result<Value> {
    match command {
        "report_export" if args["inspect_only"].as_bool() == Some(true) => {
            let path = required_path(args, "configuration_path")?;
            let source = app.snapshot.as_ref().and_then(|s| s.document.clone());
            let page = args["config_xml_code_page"]
                .as_u64()
                .or(args["config_legacy_code_page"].as_u64());
            jobs.start(move|| {let session=if source.is_none(){Some(crate::backend::ScanSession::documents(&crate::platform::backend())?)}else{None};let source=source.unwrap_or_else(||crate::document::NativeDocument{process:session.as_ref().unwrap().process_handle(),version:"metadata".into()});use base64::Engine;use std::io::Read;anyhow::ensure!(std::fs::metadata(&path)?.is_file(),"not_regular_file");let mut xml=Vec::new();std::fs::File::open(path)?.take(4_194_305).read_to_end(&mut xml)?;anyhow::ensure!(xml.len()<=4_194_304,"input_limit");let mut bytes=Vec::new();source.request(json!({"operation":"exportConfigurations","configuration":base64::engine::general_purpose::STANDARD.encode(xml),"codePage":page}),&mut bytes)?;let exports:Value=serde_json::from_slice(&bytes)?;Ok(json!({"exports":exports,"applied_to_window":false}))})
        }
        "snapshot_save" | "report_export" => {
            let path = required_path(args, "output")?;
            anyhow::ensure!(!path.exists(), "output_exists");
            let source = app
                .snapshot
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("no_snapshot"))?;
            let native = source
                .document
                .clone()
                .ok_or_else(|| anyhow::anyhow!("no_native_document"))?;
            let mut request = app.document_command(cx);
            request["maxOutputBytes"] = args["max_output_bytes"].clone();
            request["operation"] = if command == "snapshot_save" {
                "sns"
            } else {
                "report"
            }
            .into();
            let configuration = args["configuration_path"]
                .as_str()
                .map(std::path::PathBuf::from);
            let index = args["configuration_index"].as_u64().unwrap_or(0);
            let page = args["config_xml_code_page"]
                .as_u64()
                .or(args["config_legacy_code_page"].as_u64());
            jobs.start(move || {
                if let Some(config) = configuration {
                    use base64::Engine;
                    use std::io::Read;
                    let mut xml = Vec::new();
                    {
                        anyhow::ensure!(std::fs::metadata(&config)?.is_file(), "not_regular_file");
                        std::fs::File::open(config)?
                    }
                    .take(4_194_305)
                    .read_to_end(&mut xml)?;
                    anyhow::ensure!(xml.len() <= 4_194_304, "input_limit");
                    request["operation"] = "configuredReport".into();
                    request["configuration"] =
                        base64::engine::general_purpose::STANDARD.encode(xml).into();
                    request["configurationIndex"] = index.into();
                    request["codePage"] = page.into();
                }
                crate::document::save_new_atomic(&native, request, &path)?;
                Ok(json!({"output":path,"bytes":std::fs::metadata(&path)?.len()}))
            })
        }
        "snapshot_load" => {
            let inspect = args["inspect_only"].as_bool().unwrap_or(false);
            anyhow::ensure!(
                inspect || !app.scanning || args["replace"].as_bool() == Some(true),
                "scan_active"
            );
            anyhow::ensure!(jobs.active < 4, "busy");
            let path = required_path(args, "path")?;
            let page = args["legacy_code_page"]
                .as_u64()
                .map(u32::try_from)
                .transpose()?;
            let index = args["root_index"]
                .as_u64()
                .map(usize::try_from)
                .transpose()?;
            if inspect {
                return jobs.start(
                    move || match import_native(path, page, index, true, None)? {
                        ImportResult::Inspection(value) => Ok(value),
                        _ => unreachable!(),
                    },
                );
            }
            app.cancel_import();
            let generation = app.document_open_id;
            let target = app.control_window_id.clone();
            let id = jobs.reserve()?;
            let tx = jobs.tx.clone();
            let key = id.clone();
            std::thread::spawn(move || {
                let started = ImportStart {
                    tx: tx.clone(),
                    id: key.clone(),
                    window: target.clone(),
                    generation,
                };
                let result = import_native(path, page, index, false, Some(started));
                let _ = tx.send((
                    key,
                    Outcome::ImportFinished {
                        window: target,
                        generation,
                        result,
                    },
                ));
            });
            Ok(json!({"accepted":true,"job_id":id}))
        }
        _ => anyhow::bail!("unknown_command"),
    }
}
