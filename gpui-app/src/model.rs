use anyhow::{Result, bail};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct Node {
    #[serde(flatten)]
    pub metadata: NodeMetadata,
    pub id: usize,
    pub parent: Option<usize>,
    pub name: String,
    #[serde(default)]
    pub path: String,
    pub directory: bool,
    pub logical: u64,
    pub allocated: u64,
    #[serde(default)]
    pub attributes: u32,
    #[serde(default)]
    pub boundary: bool,
    #[serde(default)]
    pub error: Option<serde_json::Value>,
    #[serde(default)]
    pub children: Vec<usize>,
}
#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
pub struct NodeMetadata {
    #[serde(default)]
    pub modified: Option<f64>,
    #[serde(default)]
    pub created: Option<f64>,
    #[serde(default)]
    pub accessed: Option<f64>,
    #[serde(default, rename = "nativeType")]
    pub native_type: Option<u8>,
    #[serde(default, rename = "nativeFlags")]
    pub native_flags: Option<u8>,
}
#[derive(Debug, Deserialize, Serialize)]
pub struct Snapshot {
    #[serde(skip)]
    pub document: Option<crate::document::NativeDocument>,
    pub schema: u32,
    #[serde(default, rename = "wireVersion")]
    pub wire_version: Option<String>,
    pub root: String,
    pub cancelled: bool,
    pub files: usize,
    pub folders: usize,
    pub errors: usize,
    #[serde(default)]
    pub issues: Vec<String>,
    pub excluded: usize,
    #[serde(rename = "elapsedSeconds")]
    pub elapsed: f64,
    #[serde(default, rename = "volumeTotal")]
    pub volume_total: u64,
    #[serde(default, rename = "volumeFree")]
    pub volume_free: u64,
    #[serde(default, rename = "isVolumeRoot")]
    pub is_volume_root: bool,
    #[serde(default, rename = "volumeTraversal")]
    pub volume_traversal: Option<String>,
    pub nodes: Vec<Node>,
    #[serde(default)]
    pub tags: std::collections::HashMap<String, u8>,
}
impl Snapshot {
    /// Match native SnapshotTree lookup: visit only ancestors and their direct children.
    pub fn node_at_path(&self, path: &str) -> Option<usize> {
        if path == self.root {
            return Some(0);
        }
        let suffix = path.strip_prefix(&self.root)?;
        let windows = self.root.starts_with("\\\\") || self.root.as_bytes().get(1) == Some(&b':');
        let separator = if windows { '\\' } else { '/' };
        if !self.root.ends_with(separator) && !suffix.starts_with(separator) {
            return None;
        }
        let mut current = 0;
        for name in suffix.split(separator).filter(|part| !part.is_empty()) {
            current = self.nodes[current]
                .children
                .iter()
                .copied()
                .find(|&id| self.nodes[id].name == name)?;
        }
        (self.nodes[current].path == path).then_some(current)
    }

    pub fn validate(&self) -> Result<()> {
        if self.schema != 1 || self.nodes.is_empty() || self.nodes[0].parent.is_some() {
            bail!("지원하지 않는 스냅샷 구조입니다.")
        }
        let mut refs = vec![0u8; self.nodes.len()];
        let (mut files, mut folders) = (0, 0);
        for (id, n) in self.nodes.iter().enumerate() {
            if n.id != id || id > 0 && n.parent.is_none_or(|p| p >= id) {
                bail!("잘못된 노드 ID/parent입니다.")
            }
            if n.directory {
                folders += 1
            } else if n.metadata.native_type.is_none_or(|t| t == 2) {
                files += 1
            }
            for &child in &n.children {
                if child <= id
                    || child >= self.nodes.len()
                    || self.nodes[child].parent != Some(id)
                    || refs[child] != 0
                {
                    bail!("중복되거나 잘못된 children입니다.")
                }
                refs[child] = 1;
            }
        }
        if refs.iter().skip(1).any(|&r| r != 1) || files != self.files || folders != self.folders {
            bail!("연결 또는 파일 수가 일치하지 않습니다.")
        }
        Ok(())
    }
    pub fn load(path: &std::path::Path) -> Result<Arc<Self>> {
        Self::load_except(path, None)?.ok_or_else(|| anyhow::anyhow!("snapshot missing"))
    }
    pub fn load_except(path: &std::path::Path, version: Option<&str>) -> Result<Option<Arc<Self>>> {
        let data = std::fs::read(path)?;
        if data.starts_with(b"SSW1")
            && version.is_some()
            && crate::wire::version(&data)?.as_deref() == version
        {
            return Ok(None);
        }
        let mut s: Self = if data.starts_with(b"SSW1") {
            crate::wire::decode(&data)?
        } else {
            serde_json::from_slice(&data)?
        };
        // Native IPC omits repeated child paths. Rebuild from parent/name once;
        // old JSON files with explicit paths remain readable.
        let windows = s.root.starts_with("\\\\") || s.root.as_bytes().get(1) == Some(&b':');
        for id in 0..s.nodes.len() {
            if s.nodes[id].path.is_empty() {
                let parent = s.nodes[id]
                    .parent
                    .filter(|&p| p < id)
                    .ok_or_else(|| anyhow::anyhow!("경로를 복원할 부모가 없습니다."))?;
                let base = &s.nodes[parent].path;
                let separator = if base.ends_with('/') || windows && base.ends_with('\\') {
                    ""
                } else if windows {
                    "\\"
                } else {
                    "/"
                };
                s.nodes[id].path = format!("{}{}{}", base, separator, s.nodes[id].name);
            }
        }
        s.validate()?;
        Ok(Some(Arc::new(s)))
    }
}
/// Native overview v1: two size modes × two item kinds × bounded candidates.
pub const OVERVIEW_VERSION: u32 = 1;
pub const OVERVIEW_CANDIDATE_LIMIT: usize = 16;
const OVERVIEW_WIRE_LIMIT: usize = OVERVIEW_CANDIDATE_LIMIT * 4;

#[derive(Clone, Debug, Default, Deserialize)]
pub struct Overview {
    pub name: String,
    pub path: String,
    pub directory: bool,
    pub logical: u64,
    pub allocated: u64,
}
#[derive(Clone, Debug, Default, Deserialize)]
pub struct Progress {
    pub current: String,
    pub files: usize,
    pub folders: usize,
    pub pending: usize,
    pub errors: usize,
    #[serde(default)]
    pub excluded: Option<usize>,
    pub logical: u64,
    pub allocated: u64,
    #[serde(default)]
    pub roots: Vec<Overview>,
    /// Version 1: bounded candidates use the same observed totals as this event.
    #[serde(default, rename = "overviewVersion")]
    pub overview_version: Option<u32>,
    #[serde(default, rename = "rootFolderCount")]
    pub root_folder_count: Option<usize>,
}
impl Progress {
    /// Each kind is a disjoint candidate set; files may overlap folder totals.
    pub fn validate_overview(&self) -> Result<()> {
        if self.overview_version != Some(OVERVIEW_VERSION) {
            return Ok(());
        }
        if self.roots.len() > OVERVIEW_WIRE_LIMIT {
            bail!("overview candidate limit exceeded");
        }
        let mut paths = std::collections::HashSet::new();
        for root in &self.roots {
            if root.path.is_empty() || !paths.insert(&root.path) {
                bail!("invalid overview path");
            }
        }
        if self
            .root_folder_count
            .is_some_and(|count| count < self.roots.iter().filter(|r| r.directory).count())
        {
            bail!("overview folder count is inconsistent");
        }
        for directory in [true, false] {
            let (mut logical, mut allocated) = (0u64, 0u64);
            for root in self.roots.iter().filter(|r| r.directory == directory) {
                logical = logical
                    .checked_add(root.logical)
                    .ok_or_else(|| anyhow::anyhow!("overview logical overflow"))?;
                allocated = allocated
                    .checked_add(root.allocated)
                    .ok_or_else(|| anyhow::anyhow!("overview allocated overflow"))?;
            }
            if logical > self.logical || allocated > self.allocated {
                bail!("overview exceeds observed total");
            }
        }
        Ok(())
    }
}

pub fn bytes(value: u64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB", "PB"];
    let mut n = value as f64;
    let mut i = 0;
    while n >= 1000. && i < units.len() - 1 {
        n /= 1000.;
        i += 1
    }
    if i == 0 {
        format!("{value} B")
    } else {
        format!("{n:.1} {}", units[i])
    }
}

pub fn timestamp(value: Option<f64>) -> String {
    value
        .filter(|v| v.is_finite() && *v > -60_000_000_000.0)
        .and_then(|v| chrono::DateTime::from_timestamp_millis((v * 1000.0) as i64))
        .map(|d| {
            d.with_timezone(&chrono::Local)
                .format("%Y. %m. %d. %H:%M")
                .to_string()
        })
        .unwrap_or_else(|| "—".into())
}

/// Native getTag displays the first own color; matching independently uses all bits.
pub fn tag_color_index(mask: u8) -> u8 {
    if mask & 15 == 0 {
        0
    } else {
        ((mask & 15).trailing_zeros() + 1) as u8
    }
}
#[cfg(test)]
mod tag_tests {
    use super::*;
    #[test]
    fn native_masks_display_first_own_color() {
        for (mask, color) in [(0, 0), (1, 1), (2, 2), (4, 3), (8, 4), (12, 3), (15, 1)] {
            assert_eq!(tag_color_index(mask), color);
        }
    }
}

#[cfg(test)]
mod compact_path_tests {
    use super::*;
    #[test]
    fn compact_paths_and_hierarchy_lookup_work_for_both_path_flavors() {
        let directory = tempfile::tempdir().unwrap();
        let file = directory.path().join("wire.json");
        for root in ["/data", r"C:\data"] {
            let wire = serde_json::json!({"schema":1,"root":root,"cancelled":false,"files":1,"folders":2,"errors":0,"excluded":0,"elapsedSeconds":0.0,
                "nodes":[{"id":0,"parent":null,"name":"data","path":root,"directory":true,"logical":1,"allocated":4096,"children":[1]},
                {"id":1,"parent":0,"name":"branch","directory":true,"logical":1,"allocated":4096,"children":[2]},
                {"id":2,"parent":1,"name":"한글.zip","directory":false,"logical":1,"allocated":4096,"children":[]}]});
            std::fs::write(&file, serde_json::to_vec(&wire).unwrap()).unwrap();
            let snapshot = Snapshot::load(&file).unwrap();
            let path = format!(
                "{root}{}branch{}한글.zip",
                if root.starts_with('/') { "/" } else { "\\" },
                if root.starts_with('/') { "/" } else { "\\" }
            );
            assert_eq!(snapshot.nodes[2].path, path);
            assert_eq!(snapshot.node_at_path(&path), Some(2));
            assert_eq!(snapshot.node_at_path(&format!("{root}base/branch")), None);
            assert_eq!(snapshot.node_at_path(root), Some(0));
        }
    }
}
