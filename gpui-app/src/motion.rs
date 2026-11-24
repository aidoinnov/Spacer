use crate::layout::{Rect, Tile};
use std::{
    collections::{HashMap, HashSet},
    time::Instant,
};
pub const DURATION: f64 = 0.5;
#[expect(
    clippy::approx_constant,
    reason = "Match the original Swift animation curve exactly, including its 3.1415 constant"
)]
pub fn progress(f: f64) -> f32 {
    if f <= 0. {
        0.
    } else if f >= 1. {
        1.
    } else {
        let q = (f * 3.1415).cos().mul_add(1., 1.) * 0.5;
        (1. - q * q) as f32
    }
}
fn interpolate(a: Rect, b: Rect, p: f32) -> Rect {
    Rect {
        x: a.x + (b.x - a.x) * p,
        y: a.y + (b.y - a.y) * p,
        w: a.w + (b.w - a.w) * p,
        h: a.h + (b.h - a.h) * p,
    }
}
struct Track {
    tile: Tile,
    from: Rect,
    to: Rect,
    from_opacity: f32,
    to_opacity: f32,
}
#[derive(Default)]
pub struct Presentation {
    target: Vec<Tile>,
    tracks: Vec<Track>,
    started: Option<Instant>,
}
impl Presentation {
    pub fn frame(
        &mut self,
        next: Vec<Tile>,
        now: Instant,
        reduce_motion: bool,
    ) -> (Vec<Tile>, bool) {
        if reduce_motion {
            self.started = None;
            self.tracks.clear();
        }
        let same = self.target.len() == next.len()
            && self
                .target
                .iter()
                .zip(&next)
                .all(|(a, b)| a.path == b.path && a.rect == b.rect && a.expanded == b.expanded);
        if !same {
            let previous = self.at(now);
            self.target = next.clone();
            self.tracks.clear();
            self.started = None;
            if !previous.is_empty() && !reduce_motion {
                let old: HashMap<_, _> = previous.iter().map(|t| (t.path.as_str(), t)).collect();
                let paths: HashSet<_> = next.iter().map(|t| t.path.clone()).collect();
                for t in next {
                    let (from, alpha) = old.get(t.path.as_str()).map_or(
                        (
                            Rect {
                                x: t.rect.x + t.rect.w / 2.,
                                y: t.rect.y + t.rect.h / 2.,
                                w: 0.,
                                h: 0.,
                            },
                            0.,
                        ),
                        |old| (old.rect, old.opacity),
                    );
                    self.tracks.push(Track {
                        to: t.rect,
                        from,
                        from_opacity: alpha,
                        to_opacity: 1.,
                        tile: t,
                    });
                }
                for mut t in previous {
                    if !paths.contains(&t.path) {
                        t.interactive = false;
                        self.tracks.push(Track {
                            from: t.rect,
                            to: t.rect,
                            from_opacity: t.opacity,
                            to_opacity: 0.,
                            tile: t,
                        });
                    }
                }
                self.started = Some(now);
            }
        } else {
            self.target = next;
        }
        let active = self
            .started
            .is_some_and(|s| now.duration_since(s).as_secs_f64() < DURATION);
        if !active {
            self.started = None;
            self.tracks.clear();
        }
        (self.at(now), active)
    }
    fn at(&self, now: Instant) -> Vec<Tile> {
        let Some(start) = self.started else {
            return self.target.clone();
        };
        let p = progress(now.duration_since(start).as_secs_f64() / DURATION);
        self.tracks
            .iter()
            .filter_map(|track| {
                let opacity = track.from_opacity + (track.to_opacity - track.from_opacity) * p;
                if opacity <= 0.005 {
                    return None;
                }
                let mut t = track.tile.clone();
                t.rect = interpolate(track.from, track.to, p);
                t.opacity = opacity;
                Some(t)
            })
            .collect()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn matches_swift_curve() {
        assert_eq!(progress(0.), 0.);
        assert_eq!(progress(1.), 1.);
        assert!((progress(0.5) - 0.7499768).abs() < 1e-6);
    }
}
#[cfg(test)]
mod parity_tests {
    use super::*;
    fn tile(path: &str, x: f32) -> Tile {
        Tile {
            id: Some(1),
            path: path.into(),
            parent_path: None,
            name: path.into(),
            weight: 1,
            folder: false,
            rect: Rect {
                x,
                y: 0.,
                w: 100.,
                h: 100.,
            },
            expanded: false,
            level: 1,
            opacity: 1.,
            interactive: true,
        }
    }
    #[test]
    fn original_swift_samples() {
        let oracle: serde_json::Value =
            serde_json::from_str(include_str!("../tests/fixtures/swift-layout-motion.json"))
                .unwrap();
        for v in oracle["motion"].as_array().unwrap() {
            assert!(
                (progress(v["fraction"].as_f64().unwrap()) as f64
                    - v["progress"].as_f64().unwrap())
                .abs()
                    < 1e-6
            );
        }
    }
    #[test]
    fn outgoing_nodes_cannot_be_clicked() {
        let mut p = Presentation::default();
        let now = Instant::now();
        p.frame(vec![tile("old", 0.)], now, false);
        let (frame, active) = p.frame(vec![tile("new", 100.)], now, false);
        assert!(active);
        assert!(frame.iter().all(|t| !t.interactive));
        let (frame, active) = p.frame(
            vec![tile("new", 100.)],
            now + std::time::Duration::from_millis(500),
            false,
        );
        assert!(!active);
        assert_eq!(frame.len(), 1);
        assert_eq!(frame[0].path, "new");
        assert_eq!(frame[0].opacity, 1.);
    }
    #[test]
    fn interrupted_transition_continues_from_visible_rect() {
        let mut p = Presentation::default();
        let t = Instant::now();
        p.frame(vec![tile("same", 0.)], t, false);
        p.frame(vec![tile("same", 100.)], t, false);
        let (frame, _) = p.frame(
            vec![tile("same", 100.)],
            t + std::time::Duration::from_millis(250),
            false,
        );
        let x = frame[0].rect.x;
        let (frame, _) = p.frame(
            vec![tile("same", 200.)],
            t + std::time::Duration::from_millis(250),
            false,
        );
        assert!((frame[0].rect.x - x).abs() < 1e-5);
    }
    #[test]
    fn reduced_motion_skips_transition() {
        let mut p = Presentation::default();
        let t = Instant::now();
        p.frame(vec![tile("same", 0.)], t, false);
        let (frame, active) = p.frame(vec![tile("same", 100.)], t, true);
        assert!(!active);
        assert_eq!(frame[0].rect.x, 100.);
    }
}
