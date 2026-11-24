use crate::model::{Node, Snapshot};
use anyhow::{Result, bail};
use regex::Regex;
use std::sync::Arc;
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum SizeMode {
    #[default]
    Allocated,
    Logical,
}
impl SizeMode {
    pub fn value(self, n: &Node) -> u64 {
        match self {
            Self::Allocated => n.allocated,
            Self::Logical => n.logical,
        }
    }
}
#[derive(Clone, Debug)]
pub struct Projection {
    pub source: Arc<Snapshot>,
    pub weights: Arc<[u64]>,
    pub children: Arc<[usize]>,
    text: String,
    mode: SizeMode,
    hidden: bool,
}
impl Projection {
    #[cfg(test)]
    pub fn build(
        source: Arc<Snapshot>,
        focus: usize,
        text: &str,
        mode: SizeMode,
        hidden: bool,
    ) -> Result<Self> {
        Self::build_with_tags(source, focus, text, mode, hidden, &Default::default())
    }
    pub fn build_with_tags(
        source: Arc<Snapshot>,
        focus: usize,
        text: &str,
        mode: SizeMode,
        hidden: bool,
        tags: &std::collections::HashMap<String, u8>,
    ) -> Result<Self> {
        if let Some(document) = &source.document {
            let weights = document.weights(
                text,
                mode == SizeMode::Logical,
                hidden,
                tags,
                source.nodes.len(),
            )?;
            let mut result = Self {
                source,
                weights: weights.into(),
                children: Arc::from([]),
                text: text.into(),
                mode,
                hidden,
            };
            result.reorder(focus);
            return Ok(result);
        }
        let filter = Filter::parse(text)?;
        let mut weights = vec![0u64; source.nodes.len()];
        let mut visible = vec![false; source.nodes.len()];
        for (id, n) in source.nodes.iter().enumerate() {
            visible[id] = (id == 0 || visible[n.parent.unwrap()])
                && (id == 0 || hidden || n.attributes & 2 == 0);
            if visible[id] && !n.directory && filter.matches(n, mode) {
                weights[id] = mode.value(n)
            }
        }
        for id in (1..source.nodes.len()).rev() {
            let p = source.nodes[id].parent.unwrap();
            weights[p] = weights[p]
                .checked_add(weights[id])
                .ok_or_else(|| anyhow::anyhow!("용량 합계가 범위를 초과했습니다."))?;
        }
        let mut result = Self {
            source,
            weights: weights.into(),
            children: Arc::from([]),
            text: text.to_owned(),
            mode,
            hidden,
        };
        result.reorder(focus);
        Ok(result)
    }
    fn reorder(&mut self, focus: usize) {
        let mut children: Vec<_> = self.source.nodes[focus]
            .children
            .iter()
            .copied()
            .filter(|&id| self.weights[id] > 0)
            .collect();
        children.sort_unstable_by(|&a, &b| self.weights[b].cmp(&self.weights[a]).then(a.cmp(&b)));
        self.children = children.into();
    }
    pub fn refocus(
        &self,
        source: &Arc<Snapshot>,
        focus: usize,
        text: &str,
        mode: SizeMode,
        hidden: bool,
    ) -> Option<Self> {
        if text.contains(['>', '<'])
            || !Arc::ptr_eq(&self.source, source)
            || self.text != text
            || self.mode != mode
            || self.hidden != hidden
        {
            return None;
        }
        let mut p = self.clone();
        p.reorder(focus);
        Some(p)
    }
}
#[derive(Debug, Default)]
struct Filter {
    include: Vec<Regex>,
    exclude: Vec<Regex>,
    paths: Vec<String>,
    sizes: Vec<(bool, u64)>,
}
impl Filter {
    fn parse(text: &str) -> Result<Self> {
        let mut f = Self::default();
        let size = Regex::new(r"(?i)^([<>])\s*(\d+(?:\.\d+)?)\s*(b|kb|mb|gb|tb)?$")?;
        for t in text.split(';').map(str::trim).filter(|s| !s.is_empty()) {
            if t.starts_with(':')
                || (!t.starts_with(['>', '<']) && (t.contains('>') || t.contains('<')))
            {
                bail!("이 검증용 빌드에서 지원하지 않는 필터입니다: {t}");
            }
            if t.starts_with(['>', '<']) {
                let Some(c) = size.captures(t) else {
                    bail!("크기는 >100MB 또는 <1GB 형식으로 입력하세요.")
                };
                let units = ["b", "kb", "mb", "gb", "tb"];
                let power = units
                    .iter()
                    .position(|&s| s == c.get(3).map_or("b", |m| m.as_str()).to_ascii_lowercase())
                    .unwrap_or(0);
                let n = c[2].parse::<f64>()? * 1024f64.powi(power as i32);
                if n > u64::MAX as f64 {
                    bail!("크기가 너무 큽니다.")
                };
                f.sizes.push((&c[1] == ">", n as u64));
            } else if let Some(path) = t.strip_prefix('\\') {
                f.paths.push(path.to_lowercase());
            } else {
                let (neg, mask) = t.strip_prefix('|').map_or((false, t), |s| (true, s));
                let p = format!(
                    "(?is)\\A{}\\z",
                    regex::escape(mask).replace(r"\*", ".*").replace(r"\?", ".")
                );
                if neg {
                    f.exclude.push(Regex::new(&p)?)
                } else {
                    f.include.push(Regex::new(&p)?)
                }
            }
        }
        Ok(f)
    }
    fn matches(&self, n: &Node, mode: SizeMode) -> bool {
        let value = mode.value(n);
        self.sizes
            .iter()
            .all(|&(gt, s)| if gt { value > s } else { value < s })
            && self.paths.iter().all(|p| {
                n.path
                    .to_lowercase()
                    .replace('\\', "/")
                    .contains(&format!("/{}/", p.replace('\\', "/")))
            })
            && !self.exclude.iter().any(|r| r.is_match(&n.name))
            && (self.include.is_empty() || self.include.iter().any(|r| r.is_match(&n.name)))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn masks_and_size_match() {
        let n = Node {
            id: 0,
            parent: None,
            name: "large.zip".into(),
            path: "/r/large.zip".into(),
            directory: false,
            logical: 11000,
            allocated: 16384,
            attributes: 0,
            boundary: false,
            error: None,
            children: vec![],
            metadata: Default::default(),
        };
        assert!(
            Filter::parse("*.zip;*.dmg;>10KB")
                .unwrap()
                .matches(&n, SizeMode::Logical)
        );
        assert!(
            !Filter::parse("*.zip;|large.*")
                .unwrap()
                .matches(&n, SizeMode::Allocated)
        );
        assert!(Filter::parse(">bad").is_err());
    }
}
#[cfg(test)]
mod reuse_tests {
    use super::*;
    #[test]
    fn navigation_reuses_weight_storage() {
        let source:Snapshot=serde_json::from_str(r#"{"schema":1,"root":"/r","cancelled":false,"files":1,"folders":2,"errors":0,"excluded":0,"elapsedSeconds":1.0,"nodes":[{"id":0,"parent":null,"name":"r","path":"/r","directory":true,"logical":7,"allocated":4096,"children":[1]},{"id":1,"parent":0,"name":"child","path":"/r/child","directory":true,"logical":7,"allocated":4096,"children":[2]},{"id":2,"parent":1,"name":"f.zip","path":"/r/child/f.zip","directory":false,"logical":7,"allocated":4096,"children":[]}] }"#).unwrap();
        source.validate().unwrap();
        let source = Arc::new(source);
        let p = Projection::build(source.clone(), 0, "", SizeMode::Allocated, true).unwrap();
        let next = p
            .refocus(&source, 1, "", SizeMode::Allocated, true)
            .unwrap();
        assert!(Arc::ptr_eq(&p.weights, &next.weights));
        assert_eq!(&*next.children, &[2]);
        assert!(
            p.refocus(&source, 1, "*.zip", SizeMode::Allocated, true)
                .is_none()
        );
    }
}
