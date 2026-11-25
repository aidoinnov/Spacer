use crate::projection::Projection;
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}
impl Rect {
    pub fn inset(self, d: f32) -> Self {
        Self {
            x: self.x + d,
            y: self.y + d,
            w: (self.w - 2. * d).max(0.),
            h: (self.h - 2. * d).max(0.),
        }
    }
}
#[derive(Clone, Debug)]
pub struct Tile {
    pub id: Option<usize>,
    pub path: String,
    pub parent_path: Option<String>,
    pub name: String,
    pub weight: u64,
    pub folder: bool,
    pub rect: Rect,
    pub expanded: bool,
    pub level: usize,
    pub opacity: f32,
    pub interactive: bool,
}
// Direct port of SpaceSnifferCore/Treemap.swift, including tie ordering and insets.
pub fn layout(items: &mut [Tile], rect: Rect) {
    if rect.w <= 0. || rect.h <= 0. {
        return;
    }
    let total = items.iter().map(|t| t.weight as f64).sum::<f64>();
    if total <= 0. {
        return;
    }
    let scale = rect.w as f64 * rect.h as f64 / total;
    let mut remaining = rect;
    let (mut start, mut sum, mut low, mut high) = (0, 0., f64::INFINITY, 0f64);
    fn worst(sum: f64, low: f64, high: f64, side: f64) -> f64 {
        if sum <= 0. || side <= 0. || low <= 0. {
            return f64::INFINITY;
        }
        (side * side * high / (sum * sum)).max(sum * sum / (side * side * low))
    }
    fn place(items: &mut [Tile], r: &mut Rect, scale: f64) {
        let sum = items.iter().map(|t| t.weight as f64 * scale).sum::<f64>() as f32;
        if r.w >= r.h {
            let width = r.w.min(sum / r.h.max(0.000001));
            let mut y = r.y;
            for item in items {
                let h =
                    (r.y + r.h - y).min((item.weight as f64 * scale) as f32 / width.max(0.000001));
                item.rect = Rect {
                    x: r.x,
                    y,
                    w: width,
                    h: h.max(0.),
                };
                y += h;
            }
            r.x += width;
            r.w = (r.w - width).max(0.);
        } else {
            let height = r.h.min(sum / r.w.max(0.000001));
            let mut x = r.x;
            for item in items {
                let w =
                    (r.x + r.w - x).min((item.weight as f64 * scale) as f32 / height.max(0.000001));
                item.rect = Rect {
                    x,
                    y: r.y,
                    w: w.max(0.),
                    h: height,
                };
                x += w;
            }
            r.y += height;
            r.h = (r.h - height).max(0.);
        }
    }
    for i in 0..items.len() {
        let area = items[i].weight as f64 * scale;
        let side = remaining.w.min(remaining.h) as f64;
        if i > start
            && worst(sum + area, low.min(area), high.max(area), side) > worst(sum, low, high, side)
        {
            place(&mut items[start..i], &mut remaining, scale);
            start = i;
            sum = 0.;
            low = f64::INFINITY;
            high = 0.;
        }
        sum += area;
        low = low.min(area);
        high = high.max(area);
    }
    if start < items.len() {
        place(&mut items[start..], &mut remaining, scale)
    }
}
pub fn tiles(
    p: &Projection,
    root: usize,
    depth: usize,
    selected: Option<usize>,
    bounds: Rect,
) -> Vec<Tile> {
    let mut selection = std::collections::HashSet::new();
    let mut cursor = selected;
    while let Some(id) = cursor {
        selection.insert(id);
        if id == root {
            break;
        }
        cursor = p.source.nodes[id].parent;
    }
    if !selection.contains(&root) {
        selection.clear();
    }
    fn children(p: &Projection, id: usize) -> Vec<Tile> {
        let mut nodes: Vec<_> = p.source.nodes[id]
            .children
            .iter()
            .copied()
            .filter(|&i| p.weights[i] > 0)
            .collect();
        nodes.sort_unstable_by(|&a, &b| p.weights[b].cmp(&p.weights[a]).then(a.cmp(&b)));
        let remainder = if nodes.len() > 2048 {
            let omitted = nodes.len() - 2047;
            let weight = nodes[2047..].iter().map(|&id| p.weights[id]).sum();
            nodes.truncate(2047);
            Some(Tile {
                id: None,
                path: format!("{}\0remainder", p.source.nodes[id].path),
                parent_path: Some(p.source.nodes[id].path.clone()),
                name: format!("나머지 {omitted}개 · 목록에서 탐색"),
                weight,
                folder: false,
                rect: Rect::default(),
                expanded: false,
                level: 0,
                opacity: 1.,
                interactive: false,
            })
        } else {
            None
        };
        let mut tiles: Vec<_> = nodes
            .into_iter()
            .map(|id| {
                let n = &p.source.nodes[id];
                Tile {
                    id: Some(id),
                    path: n.path.clone(),
                    parent_path: n.parent.map(|id| p.source.nodes[id].path.clone()),
                    name: n.name.clone(),
                    weight: p.weights[id],
                    folder: n.directory,
                    rect: Rect::default(),
                    expanded: false,
                    level: 0,
                    opacity: 1.,
                    interactive: true,
                }
            })
            .collect();
        tiles.extend(remainder);
        tiles.sort_unstable_by(|a, b| b.weight.cmp(&a.weight).then(a.id.cmp(&b.id)));
        tiles
    }
    fn visit(
        mut t: Tile,
        p: &Projection,
        depth: usize,
        selection: &std::collections::HashSet<usize>,
        out: &mut Vec<Tile>,
    ) {
        if t.rect.w < 2. || t.rect.h < 2. {
            return;
        }
        t.rect = t.rect.inset(1.5);
        if t.rect.w <= 1. || t.rect.h <= 1. {
            return;
        }
        t.expanded = t.folder
            && (t.level < depth || t.id.is_some_and(|id| selection.contains(&id)))
            && t.rect.w > 65.
            && t.rect.h > 62.;
        let expanded = t.expanded;
        let id = t.id;
        let r = t.rect;
        let level = t.level;
        out.push(t);
        if expanded {
            let mut kids = children(p, id.unwrap());
            layout(
                &mut kids,
                Rect {
                    x: r.x + 3.,
                    y: r.y + 25.,
                    w: r.w - 6.,
                    h: r.h - 28.,
                },
            );
            for mut child in kids {
                child.level = level + 1;
                visit(child, p, depth, selection, out)
            }
        }
    }
    let mut roots = if !p.source.nodes[root].directory {
        let node = &p.source.nodes[root];
        vec![Tile {
            id: Some(root),
            path: node.path.clone(),
            parent_path: node.parent.map(|id| p.source.nodes[id].path.clone()),
            name: node.name.clone(),
            weight: p.weights[root],
            folder: false,
            rect: bounds.inset(10.),
            expanded: false,
            level: 1,
            opacity: 1.,
            interactive: true,
        }]
    } else {
        children(p, root)
    };
    layout(&mut roots, bounds.inset(10.));
    let mut output = Vec::new();
    for mut t in roots {
        t.level = 1;
        visit(t, p, depth, &selection, &mut output)
    }
    output
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn matches_original_swift_geometry() {
        let oracle: serde_json::Value =
            serde_json::from_str(include_str!("../tests/fixtures/swift-layout-motion.json"))
                .unwrap();
        for case in oracle["cases"].as_array().unwrap() {
            let mut items: Vec<_> = case["weights"]
                .as_array()
                .unwrap()
                .iter()
                .enumerate()
                .map(|(id, w)| Tile {
                    id: Some(id),
                    path: id.to_string(),
                    parent_path: None,
                    name: id.to_string(),
                    weight: w.as_f64().unwrap() as u64,
                    folder: false,
                    rect: Rect::default(),
                    expanded: false,
                    level: 0,
                    opacity: 1.,
                    interactive: true,
                })
                .collect();
            layout(
                &mut items,
                Rect {
                    x: 10.,
                    y: 20.,
                    w: 800.,
                    h: 500.,
                },
            );
            for expected in case["tiles"].as_array().unwrap() {
                let id = expected["id"].as_f64().unwrap() as usize;
                let r = items[id].rect;
                for (key, value) in [("x", r.x), ("y", r.y), ("w", r.w), ("h", r.h)] {
                    assert!(
                        (value as f64 - expected[key].as_f64().unwrap()).abs() < 0.001,
                        "id={id} key={key}"
                    );
                }
            }
            let area: f32 = items.iter().map(|t| t.rect.w * t.rect.h).sum();
            assert!((area - 400000.).abs() < 0.2);
        }
    }
}
type GeometryKey = (usize, usize, usize, Option<usize>, Rect);
pub struct GeometryCache {
    key: Option<GeometryKey>,
    source: Option<std::sync::Arc<crate::model::Snapshot>>,
    items: Vec<Tile>,
    pending: Option<std::sync::mpsc::Receiver<Vec<Tile>>>,
    worker: crate::latest_work::LatestWork,
}
impl Default for GeometryCache {
    fn default() -> Self {
        Self {
            key: None,
            source: None,
            items: Vec::new(),
            pending: None,
            worker: crate::latest_work::LatestWork::new(),
        }
    }
}
impl GeometryCache {
    /// No map is mounted in empty/list/progress views. Discard its obsolete
    /// receiver so their readiness never depends on a future canvas paint.
    pub fn suspend(&mut self) {
        self.pending = None;
        self.key = None;
        self.source = None;
        self.items.clear();
    }
    pub fn statistics(&self) -> crate::latest_work::Statistics {
        self.worker.statistics()
    }
    pub fn pending(&self) -> bool {
        self.pending.is_some()
    }
    pub fn get(
        &mut self,
        p: &Projection,
        root: usize,
        depth: usize,
        selected: Option<usize>,
        bounds: Rect,
    ) -> Vec<Tile> {
        let key = (p.weights.as_ptr() as usize, root, depth, selected, bounds);
        if self.key != Some(key)
            || self
                .source
                .as_ref()
                .is_none_or(|s| !std::sync::Arc::ptr_eq(s, &p.source))
        {
            if self.key.is_none_or(|old| old.1 != root)
                || self
                    .source
                    .as_ref()
                    .is_none_or(|s| !std::sync::Arc::ptr_eq(s, &p.source))
            {
                self.items.clear();
            }
            self.key = Some(key);
            self.source = Some(p.source.clone());
            let projection = p.clone();
            self.pending = Some(
                self.worker
                    .submit(move || tiles(&projection, root, depth, selected, bounds)),
            );
        }
        if let Some(rx) = &self.pending
            && let Ok(items) = rx.try_recv()
        {
            self.items = items;
            self.pending = None;
        }
        let mut items = self.items.clone();
        if self.pending.is_some() {
            for tile in &mut items {
                tile.interactive = false;
            }
        }
        items
    }
}

/// Bounded coarse map while the native engine is still collecting the tree.
/// Large-file rankings overlap folder totals, so never mix both sets in one map.
pub fn overview_tiles(
    progress: &crate::model::Progress,
    mode: crate::projection::SizeMode,
    bounds: Rect,
) -> Vec<Tile> {
    let value = |n: &crate::model::Overview| {
        if mode == crate::projection::SizeMode::Logical {
            n.logical
        } else {
            n.allocated
        }
    };
    let has_folders = progress.roots.iter().any(|n| n.directory && value(n) > 0);
    let mut seen = std::collections::HashSet::new();
    let mut candidates: Vec<_> = progress
        .roots
        .iter()
        .filter(|n| n.directory == has_folders && value(n) > 0)
        .filter(|n| seen.insert(n.path.as_str()))
        .collect();
    candidates.sort_unstable_by(|a, b| value(b).cmp(&value(a)).then(a.path.cmp(&b.path)));
    let mut items: Vec<_> = candidates
        .into_iter()
        .take(crate::model::OVERVIEW_CANDIDATE_LIMIT)
        .map(|n| Tile {
            id: None,
            path: n.path.clone(),
            parent_path: None,
            name: n.name.clone(),
            weight: value(n),
            folder: n.directory,
            rect: Rect::default(),
            expanded: false,
            level: 1,
            opacity: 1.,
            interactive: n.directory && !n.path.is_empty(),
        })
        .collect();
    let total = if mode == crate::projection::SizeMode::Logical {
        progress.logical
    } else {
        progress.allocated
    };
    let covered = items
        .iter()
        .fold(0u64, |sum, t| sum.saturating_add(t.weight));
    let omitted_folders = progress
        .root_folder_count
        .unwrap_or(0)
        .saturating_sub(items.iter().filter(|item| item.folder).count());
    let remainder = total.saturating_sub(covered);
    if remainder > 0 {
        items.push(Tile {
            id: None,
            path: "sniffer:overview:remainder".into(),
            parent_path: None,
            name: match progress.overview_version {
                Some(crate::model::OVERVIEW_VERSION) if omitted_folders > 0 => {
                    format!("기타 항목 (폴더 {omitted_folders}개 포함)")
                }
                Some(crate::model::OVERVIEW_VERSION) => "기타 항목".into(),
                _ if progress.roots.is_empty() => "폴더 집계 대기 중".into(),
                _ => "기타 집계".into(),
            },
            weight: remainder,
            folder: true,
            rect: Rect::default(),
            expanded: false,
            level: 1,
            opacity: 1.,
            interactive: false,
        });
    }
    items.sort_unstable_by(|a, b| b.weight.cmp(&a.weight).then(a.path.cmp(&b.path)));
    layout(&mut items, bounds.inset(10.));
    for t in &mut items {
        t.rect = t.rect.inset(1.5);
    }
    items
}

#[cfg(test)]
mod overview_tests {
    use super::*;
    use crate::{
        model::{Overview, Progress},
        projection::SizeMode,
    };
    fn entry(path: &str, directory: bool, size: u64) -> Overview {
        Overview {
            name: path.into(),
            path: path.into(),
            directory,
            logical: size / 2,
            allocated: size,
        }
    }
    #[test]
    fn partial_scan_draws_before_a_snapshot_exists() {
        let p = Progress {
            allocated: 100,
            logical: 50,
            roots: vec![entry("/Code", true, 70), entry("/Code/a.zip", false, 20)],
            ..Default::default()
        };
        let tiles = overview_tiles(
            &p,
            SizeMode::Allocated,
            Rect {
                x: 0.,
                y: 0.,
                w: 800.,
                h: 500.,
            },
        );
        assert_eq!(tiles.len(), 2);
        assert_eq!(tiles.iter().map(|t| t.weight).sum::<u64>(), 100);
        assert!(
            tiles
                .iter()
                .all(|t| t.rect.w > 1. && t.rect.h > 1. && t.id.is_none())
        );
        assert!(!tiles.iter().any(|t| t.path == "/Code/a.zip"));
    }
    #[test]
    fn file_only_overview_and_logical_mode_are_supported() {
        let p = Progress {
            allocated: 100,
            logical: 50,
            roots: vec![entry("/a.zip", false, 80)],
            ..Default::default()
        };
        let tiles = overview_tiles(
            &p,
            SizeMode::Logical,
            Rect {
                x: 0.,
                y: 0.,
                w: 800.,
                h: 500.,
            },
        );
        assert_eq!(tiles.iter().map(|t| t.weight).sum::<u64>(), 50);
        assert_eq!(tiles[0].weight, 40);
    }
    #[test]
    fn eight_known_folders_have_no_synthetic_remainder() {
        let p = Progress {
            allocated: 800,
            logical: 400,
            overview_version: Some(1),
            roots: (0..8)
                .map(|i| entry(&format!("/d{i}"), true, 100))
                .collect(),
            ..Default::default()
        };
        for mode in [SizeMode::Allocated, SizeMode::Logical] {
            let tiles = overview_tiles(
                &p,
                mode,
                Rect {
                    x: 0.,
                    y: 0.,
                    w: 800.,
                    h: 500.,
                },
            );
            assert_eq!(tiles.len(), 8);
            assert!(
                tiles
                    .iter()
                    .all(|t| t.interactive && t.path != "sniffer:overview:remainder")
            );
        }
    }
    #[test]
    fn bounded_candidates_are_ranked_for_the_selected_size_mode() {
        let mut roots: Vec<_> = (0..32)
            .map(|i| entry(&format!("/d{i:02}"), true, 32 - i))
            .collect();
        for (i, root) in roots.iter_mut().enumerate() {
            root.logical = i as u64;
        }
        let p = Progress {
            allocated: 528,
            logical: 496,
            roots,
            overview_version: Some(1),
            ..Default::default()
        };
        let bounds = Rect {
            x: 0.,
            y: 0.,
            w: 800.,
            h: 500.,
        };
        for mode in [SizeMode::Allocated, SizeMode::Logical] {
            let tiles = overview_tiles(&p, mode, bounds);
            let named: Vec<_> = tiles.iter().filter(|t| t.interactive).collect();
            assert_eq!(named.len(), 16);
            assert!(named.iter().all(|t| if mode == SizeMode::Logical {
                t.weight >= 16
            } else {
                t.weight >= 17
            }));
            assert_eq!(
                tiles.iter().map(|t| t.weight).sum::<u64>(),
                if mode == SizeMode::Logical { 496 } else { 528 }
            );
            assert_eq!(
                tiles.iter().find(|t| !t.interactive).unwrap().name,
                "기타 항목"
            );
        }
    }
    #[test]
    fn old_progress_remains_compatible_without_claiming_unvisited_bytes() {
        let p: Progress = serde_json::from_value(serde_json::json!({
            "current":"/", "files":1,"folders":1,"pending":1,"errors":0,
            "logical":50,"allocated":100,"roots":[]
        }))
        .unwrap();
        let bounds = Rect {
            x: 0.,
            y: 0.,
            w: 800.,
            h: 500.,
        };
        assert_eq!(
            overview_tiles(&p, SizeMode::Allocated, bounds)[0].name,
            "폴더 집계 대기 중"
        );
        let p = Progress {
            roots: vec![entry("/a", true, 20)],
            ..p
        };
        assert_eq!(
            overview_tiles(&p, SizeMode::Allocated, bounds)[0].name,
            "기타 집계"
        );
    }
    #[test]
    fn inconsistent_new_overview_is_rejected_instead_of_saturating_silently() {
        let mut p = Progress {
            allocated: 10,
            logical: 5,
            overview_version: Some(1),
            roots: vec![entry("/a", true, 20)],
            ..Default::default()
        };
        assert!(p.validate_overview().is_err());
        p.allocated = 100;
        p.logical = 50;
        assert!(p.validate_overview().is_ok());
        p.roots.push(entry("/a", true, 20));
        assert!(p.validate_overview().is_err());
        p.roots = (0..65).map(|i| entry(&format!("/{i}"), false, 1)).collect();
        assert!(p.validate_overview().is_err());
    }
    #[test]
    fn sparse_folder_is_visible_in_logical_mode() {
        let p = Progress {
            logical: 100,
            allocated: 0,
            overview_version: Some(1),
            root_folder_count: Some(1),
            roots: vec![Overview {
                name: "sparse".into(),
                path: "/sparse".into(),
                directory: true,
                logical: 100,
                allocated: 0,
            }],
            ..Default::default()
        };
        assert!(p.validate_overview().is_ok());
        let tiles = overview_tiles(
            &p,
            SizeMode::Logical,
            Rect {
                x: 0.,
                y: 0.,
                w: 800.,
                h: 500.,
            },
        );
        assert_eq!(tiles.len(), 1);
        assert_eq!(tiles[0].weight, 100);
        let invalid = Progress {
            root_folder_count: Some(0),
            ..p
        };
        assert!(invalid.validate_overview().is_err());
    }
    #[test]
    fn actual_native_trace_survives_decode_validation_and_layout() {
        // Three events from the owned 65,536-file native oracle: early, middle, final.
        let events: Vec<Progress> =
            serde_json::from_str(include_str!("../tests/fixtures/progress-overview-v1.json"))
                .unwrap();
        assert_eq!(events.len(), 3);
        for event in &events {
            event.validate_overview().unwrap();
            for mode in [SizeMode::Allocated, SizeMode::Logical] {
                let tiles = overview_tiles(
                    event,
                    mode,
                    Rect {
                        x: 0.,
                        y: 0.,
                        w: 800.,
                        h: 500.,
                    },
                );
                assert!(tiles.iter().all(|t| t.interactive));
                assert_eq!(
                    tiles.iter().map(|t| t.weight).sum::<u64>(),
                    if mode == SizeMode::Logical {
                        event.logical
                    } else {
                        event.allocated
                    }
                );
            }
        }
        assert_eq!(
            events
                .last()
                .unwrap()
                .roots
                .iter()
                .filter(|r| r.directory)
                .count(),
            8
        );
    }
    #[test]
    fn aggregate_only_progress_is_still_visible() {
        let p = Progress {
            allocated: 100,
            ..Default::default()
        };
        assert_eq!(
            overview_tiles(
                &p,
                SizeMode::Allocated,
                Rect {
                    x: 0.,
                    y: 0.,
                    w: 800.,
                    h: 500.
                }
            )
            .len(),
            1
        );
    }
}
#[cfg(test)]
mod bounded_tests {
    use super::*;
    #[test]
    fn leaving_the_canvas_discards_pending_geometry_and_reentry_rebuilds() {
        let source:crate::model::Snapshot=serde_json::from_value(serde_json::json!({"schema":1,"root":"/single.txt","cancelled":false,"files":1,"folders":0,"errors":0,"excluded":0,"elapsedSeconds":0,"nodes":[{"id":0,"parent":null,"name":"single.txt","path":"/single.txt","directory":false,"logical":7,"allocated":4096,"children":[]}]})).unwrap();
        let projection = Projection::build(
            std::sync::Arc::new(source),
            0,
            "",
            crate::projection::SizeMode::Logical,
            true,
        )
        .unwrap();
        let mut cache = GeometryCache::default();
        let bounds = Rect {
            x: 0.,
            y: 0.,
            w: 800.,
            h: 600.,
        };
        cache.get(&projection, 0, 3, None, bounds);
        cache.suspend();
        assert!(!cache.pending());
        assert!(cache.items.is_empty() && cache.source.is_none());
        cache.get(&projection, 0, 3, None, bounds);
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        while cache.pending() && std::time::Instant::now() < deadline {
            std::thread::sleep(std::time::Duration::from_millis(1));
            cache.get(&projection, 0, 3, None, bounds);
        }
        assert!(!cache.pending());
        assert_eq!(cache.items.len(), 1);
        assert_eq!(cache.items[0].path, "/single.txt");
    }
    #[test]
    fn a_file_saved_as_snapshot_root_still_has_a_visible_tile() {
        let source:crate::model::Snapshot=serde_json::from_value(serde_json::json!({"schema":1,"root":"/single.txt","cancelled":false,"files":1,"folders":0,"errors":0,"excluded":0,"elapsedSeconds":0,"nodes":[{"id":0,"parent":null,"name":"single.txt","path":"/single.txt","directory":false,"logical":7,"allocated":4096,"children":[]}]})).unwrap();
        let projection = Projection::build(
            std::sync::Arc::new(source),
            0,
            "",
            crate::projection::SizeMode::Logical,
            true,
        )
        .unwrap();
        let result = tiles(
            &projection,
            0,
            3,
            None,
            Rect {
                x: 0.,
                y: 0.,
                w: 800.,
                h: 600.,
            },
        );
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, Some(0));
        assert!(result[0].rect.w > 700.);
        assert!(result[0].interactive);
    }
    #[test]
    fn very_wide_folder_keeps_weight_in_an_explicit_noninteractive_remainder() {
        let count = 5000;
        let mut nodes = vec![
            serde_json::json!({"id":0,"parent":null,"path":"/r","name":"r","directory":true,"logical":count,"allocated":count,"children":(1..=count).collect::<Vec<_>>()}),
        ];
        for id in 1..=count {
            nodes.push(serde_json::json!({"id":id,"parent":0,"path":format!("/r/f{id}"),"name":format!("f{id}"),"directory":false,"logical":1,"allocated":1,"children":[]}));
        }
        let source:crate::model::Snapshot=serde_json::from_value(serde_json::json!({"schema":1,"root":"/r","cancelled":false,"files":count,"folders":1,"errors":0,"excluded":0,"elapsedSeconds":0,"nodes":nodes})).unwrap();
        let projection = Projection::build(
            std::sync::Arc::new(source),
            0,
            "",
            crate::projection::SizeMode::Logical,
            true,
        )
        .unwrap();
        let tiles = tiles(
            &projection,
            0,
            3,
            None,
            Rect {
                x: 0.,
                y: 0.,
                w: 1000.,
                h: 700.,
            },
        );
        assert!(tiles.len() <= 2048);
        let remainder = tiles.iter().find(|t| t.id.is_none()).unwrap();
        assert!(!remainder.interactive);
        assert_eq!(remainder.weight, 2953);
        assert_eq!(tiles.iter().map(|t| t.weight).sum::<u64>(), 5000);
    }
}
