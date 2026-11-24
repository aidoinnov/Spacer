//! Native XML selection and output stay frozen across asynchronous dialogs.
use super::app::Explorer;
use base64::Engine;
use gpui_kit::*;
impl Explorer {
    pub(super) fn configured_export(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(source) = self.snapshot.clone() else {
            return;
        };
        let Some(document) = source.document.clone() else {
            return;
        };
        let mut command = serde_json::json!({"operation":"configuredReport","root":self.focus,
            "filter":self.filter_input.read(cx).value().to_string(),"logical":self.mode==crate::projection::SizeMode::Logical,
            "hidden":self.hidden,"tags":self.tags});
        let chosen = cx.prompt_for_paths(PathPromptOptions {
            files: true,
            directories: false,
            multiple: false,
            prompt: Some("보고서 설정 XML · 템플릿 선택".into()),
        });
        cx.spawn_in(window,async move|this,cx| {
            let result=async {
                let Some(paths)=chosen.await?? else {return Ok(())};
                let Some(path)=paths.into_iter().next() else {return Ok(())};
                let labels=super::document_choices::LEGACY_ENCODINGS.iter().map(|(label,_)|label.to_string()).collect();
                let encoding=this.update_in(cx,|this,window,cx| {window.focus(&this.focus_handle,cx);this.ask_document_choice("설정 XML의 원본 코드 페이지",labels,cx)})?;
                let Ok(Some(encoding))=encoding.await else {return Ok(())};
                let code_page=super::document_choices::LEGACY_ENCODINGS[encoding].1;
                command["codePage"]=code_page.into();
                let native=document.clone();
                let (encoded,configs)=cx.background_executor().spawn(async move {
                    use std::io::Read;
                    let mut xml=Vec::new();anyhow::ensure!(std::fs::metadata(&path)?.is_file(),"일반 XML 파일을 선택하세요.");std::fs::File::open(path)?.take(4_194_305).read_to_end(&mut xml)?;
                    anyhow::ensure!(xml.len()<=4_194_304,"설정 XML은 4MiB 이하여야 합니다.");
                    let encoded=base64::engine::general_purpose::STANDARD.encode(xml);
                    let mut bytes=Vec::new();native.request(serde_json::json!({"operation":"exportConfigurations","configuration":encoded,"codePage":code_page}),&mut bytes)?;
                    let configs:Vec<serde_json::Value>=serde_json::from_slice(&bytes)?;
                    anyhow::ensure!(!configs.is_empty(),"보고서 설정이 없습니다.");
                    Ok::<_,anyhow::Error>((encoded,configs))
                }).await?;
                let index=if configs.len()==1 {0} else {
                    let labels=configs.iter().map(|v|v["description"].as_str().unwrap_or("보고서").to_string()).collect();
                    let answer=this.update_in(cx,|this,window,cx| {window.focus(&this.focus_handle,cx);this.ask_document_choice("보고서 형식을 선택하세요",labels,cx)})?;
                    let Ok(Some(index))=answer.await else {return Ok(())};index
                };
                command["configuration"]=encoded.into();command["configurationIndex"]=index.into();
                let filename=safe_filename(configs[index]["filename"].as_str().unwrap_or("SpaceSniffer"));
                let path=this.update(cx,|_,cx|cx.prompt_for_new_path(&std::env::home_dir().unwrap_or_default(),Some(&filename)))?;
                let Some(path)=path.await?? else {return Ok(())};let display=path.clone();
                cx.background_executor().spawn(async move {crate::document::save_atomic(&document,command,&path)}).await?;
                this.update(cx,|this,cx| {this.status=format!("저장 완료: {}",display.display());cx.notify();})?;
                Ok::<_,anyhow::Error>(())
            }.await;
            if let Err(error)=result {let _=this.update(cx,|this,cx| {this.status=format!("보고서 오류: {error}");cx.notify();});}
        }).detach();
    }
}
fn safe_filename(value: &str) -> String {
    let name: String = value
        .chars()
        .take(160)
        .map(|c| {
            if c.is_control() || "/\\:*?\"<>|".contains(c) {
                '_'
            } else {
                c
            }
        })
        .collect();
    let name = name.trim_matches([' ', '.']);
    if name.is_empty() {
        "SpaceSniffer.txt".into()
    } else if name.contains('.') {
        name.into()
    } else {
        format!("{name}.txt")
    }
}
