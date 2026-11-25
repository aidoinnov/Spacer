use std::path::{Path, PathBuf};
/// Paths survive scanner rebuilds; numeric IDs are local to one completed snapshot.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Location {
    pub document: PathBuf,
    pub focus: PathBuf,
}
impl Location {
    pub fn root(path: PathBuf) -> Self {
        Self {
            document: path.clone(),
            focus: path,
        }
    }
}
fn windows_path(text: &str) -> bool {
    text.starts_with("\\\\") || text.as_bytes().get(1) == Some(&b':')
}
pub fn label(path: &Path) -> String {
    let text = path.to_string_lossy();
    let windows = windows_path(&text);
    text.trim_end_matches(|c| c == '/' || windows && c == '\\')
        .rsplit(|c| c == '/' || windows && c == '\\')
        .next()
        .filter(|s| !s.is_empty())
        .unwrap_or(&text)
        .to_owned()
}
pub fn contains(scope: &Path, path: &Path) -> bool {
    let scope = scope.to_string_lossy();
    let path = path.to_string_lossy();
    if scope == path {
        return true;
    }
    path.strip_prefix(scope.as_ref()).is_some_and(|suffix| {
        scope.ends_with('/')
            || windows_path(&scope) && scope.ends_with('\\')
            || suffix.starts_with('/')
            || windows_path(&scope) && suffix.starts_with('\\')
    })
}
/// Keep cached/offline spelling intact; resolve native aliases only when the
/// requested spelling is outside the lexical scope (e.g. Windows short names).
pub fn resolve_contained_path(
    scope: &Path,
    path: PathBuf,
    normalize: impl FnOnce(&Path) -> PathBuf,
) -> Option<PathBuf> {
    let path = if contains(scope, &path) {
        path
    } else {
        normalize(&path)
    };
    contains(scope, &path).then_some(path)
}
pub fn parent(path: &Path) -> Option<PathBuf> {
    let text = path.to_string_lossy();
    let windows = windows_path(&text);
    let trimmed = text.trim_end_matches(|c| c == '/' || windows && c == '\\');
    let index = trimmed.rfind(|c| c == '/' || windows && c == '\\')?;
    let end = if index == 0 || (index == 2 && trimmed.as_bytes().get(1) == Some(&b':')) {
        index + 1
    } else {
        index
    };
    Some(PathBuf::from(&trimmed[..end]))
}
pub fn breadcrumbs(scope: &Path, focus: &Path) -> Vec<PathBuf> {
    let mut paths = vec![];
    let mut cursor = Some(focus.to_path_buf());
    while let Some(path) = cursor {
        if !contains(scope, &path) {
            break;
        }
        cursor = if path == scope { None } else { parent(&path) };
        paths.push(path);
    }
    paths.reverse();
    paths
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_aliases_resolve_without_rewriting_cached_snapshot_paths() {
        let scope = Path::new(r"C:\Users\long-user\data");
        let cached = scope.join("child");
        assert_eq!(
            resolve_contained_path(scope, cached.clone(), |_| panic!(
                "cached paths need no I/O"
            )),
            Some(cached.clone())
        );
        let alias = PathBuf::from(r"C:\Users\LONGUS~1\data\child");
        assert_eq!(
            resolve_contained_path(scope, alias.clone(), |path| {
                assert_eq!(path, alias);
                cached.clone()
            }),
            Some(cached)
        );
        assert!(
            resolve_contained_path(scope, PathBuf::from("/outside"), |path| path.into()).is_none()
        );
    }
    #[test]
    fn windows_snapshot_paths_work_on_any_host() {
        let scope = Path::new(r"C:\data");
        let focus = Path::new(r"C:\data\alpha\nested");
        assert_eq!(
            breadcrumbs(scope, focus),
            vec![
                PathBuf::from(r"C:\data"),
                PathBuf::from(r"C:\data\alpha"),
                focus.into()
            ]
        );
        assert!(!contains(scope, Path::new(r"C:\database\x")));
        assert_eq!(label(focus), "nested");
        assert_eq!(parent(Path::new(r"C:\data")).unwrap(), Path::new(r"C:\"));
        assert_eq!(
            parent(Path::new("/data/name\\part/file")).unwrap(),
            Path::new("/data/name\\part")
        );
    }
    #[test]
    fn scoped_breadcrumbs_stop_at_original_root() {
        let root = std::env::temp_dir().join("scope");
        let focus = root.join("Code").join("src");
        assert_eq!(
            breadcrumbs(&root, &focus),
            vec![root.clone(), root.join("Code"), focus]
        );
    }
}
