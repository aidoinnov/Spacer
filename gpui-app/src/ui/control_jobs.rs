//! Bounded asynchronous jobs and native import ownership.
use serde_json::{Value, json};
use std::{
    collections::{HashMap, VecDeque},
    sync::mpsc,
    time::Duration,
};
pub(super) enum ImportResult {
    Document(
        std::sync::Arc<crate::model::Snapshot>,
        crate::backend::ScanSession,
    ),
    Inspection(Value),
}
pub(super) enum Outcome {
    Value(Value),
    ImportStarted {
        window: String,
        generation: u64,
        process: std::sync::Arc<crate::document::NativeProcess>,
    },
    ImportFinished {
        window: String,
        generation: u64,
        result: anyhow::Result<ImportResult>,
    },
}
pub(super) struct Jobs {
    pub(super) values: HashMap<String, Value>,
    pub(super) order: VecDeque<String>,
    pub(super) next: u64,
    pub(super) active: usize,
    pub(super) tx: mpsc::Sender<(String, Outcome)>,
    pub(super) rx: mpsc::Receiver<(String, Outcome)>,
}
impl Jobs {
    pub(super) fn new() -> Self {
        let (tx, rx) = mpsc::channel();
        Self {
            values: HashMap::new(),
            order: VecDeque::new(),
            next: 0,
            active: 0,
            tx,
            rx,
        }
    }
    pub(super) fn reserve(&mut self) -> anyhow::Result<String> {
        anyhow::ensure!(self.active < 4, "busy");
        self.next += 1;
        let id = format!("{}-{}", std::process::id(), self.next);
        self.active += 1;
        if self.order.len() >= 32
            && let Some(old) = self.order.pop_front()
        {
            self.values.remove(&old);
        }
        self.order.push_back(id.clone());
        self.values
            .insert(id.clone(), json!({"job_id":id,"phase":"running"}));
        Ok(id)
    }
    pub(super) fn start(
        &mut self,
        operation: impl FnOnce() -> anyhow::Result<Value> + Send + 'static,
    ) -> anyhow::Result<Value> {
        let id = self.reserve()?;
        let tx = self.tx.clone();
        let key = id.clone();
        std::thread::spawn(move || {
            let result = match operation() {
                Ok(value) => json!({"job_id":key,"phase":"completed","result":value}),
                Err(error) => json!({"job_id":key,"phase":"failed","error":error.to_string()}),
            };
            let _ = tx.send((key, Outcome::Value(result)));
        });
        Ok(json!({"job_id":id,"accepted":true}))
    }
}
pub(super) struct ImportStart {
    pub tx: mpsc::Sender<(String, Outcome)>,
    pub id: String,
    pub window: String,
    pub generation: u64,
}
pub(super) fn import_native(
    path: std::path::PathBuf,
    page: Option<u32>,
    index: Option<usize>,
    inspect: bool,
    started: Option<ImportStart>,
) -> anyhow::Result<ImportResult> {
    use crate::backend::{Event, ScanSession};
    if path
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("json"))
    {
        anyhow::bail!("Native SNS/DU is required for automated import");
    }
    let session = if inspect {
        ScanSession::inspect(&crate::platform::backend(), &path)?
    } else {
        ScanSession::open(&crate::platform::backend(), &path)?
    };
    if let Some(ImportStart {
        tx,
        id,
        window,
        generation,
    }) = started
    {
        let _ = tx.send((
            id,
            Outcome::ImportStarted {
                window,
                generation,
                process: session.process_handle(),
            },
        ));
    }
    let mut chose_root = false;
    loop {
        match session.events.recv_timeout(Duration::from_secs(120))? {
            Event::ImportCodePage => {
                let page = page.ok_or_else(|| anyhow::anyhow!("legacy_code_page_required"))?;
                anyhow::ensure!(page > 0, "invalid_code_page");
                session.send(&format!("codepage {page}"));
            }
            Event::ImportRoots(roots) => {
                let index = index.ok_or_else(|| anyhow::anyhow!("root_index_required"))?;
                anyhow::ensure!(index < roots.len(), "invalid_root_index");
                session.send(&format!("select {index}"));
                chose_root = true;
            }
            Event::ImportInspection(roots) => {
                return Ok(ImportResult::Inspection(
                    json!({"roots":roots,"applied_to_window":false}),
                ));
            }
            Event::Complete(source) => {
                anyhow::ensure!(chose_root || index.unwrap_or(0) == 0, "invalid_root_index");
                return Ok(ImportResult::Document(source, session));
            }
            Event::Failure(error) => anyhow::bail!(error),
            _ => {}
        }
    }
}
