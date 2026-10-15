//! Compute a [`Manifest`] for a directory tree.
//!
//! Walks `root` with `walkdir`, hashes regular files with SHA-256, and
//! filters out anything that matches the compiled exclude patterns. The
//! receiver's own state directory (`.localsend-sync/`) is always excluded.
//!
//! The manifest is sorted by path so it can be diffed with a binary search
//! and so a byte-equal manifest is a fast "no changes" check.

use crate::sync::{Entry, Manifest, MANIFEST_VERSION};
use anyhow::{Context, Result};
use globset::{Glob, GlobSet, GlobSetBuilder};
use sha2::{Digest, Sha256};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

/// Compile gitignore-style patterns into a `GlobSet`. Empty lines and
/// comments (lines starting with `#`) are skipped. Patterns must use forward
/// slashes.
pub fn compile_excludes<I, S>(patterns: I) -> Result<GlobSet>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let mut builder = GlobSetBuilder::new();
    for pat in patterns {
        let pat = pat.as_ref();
        if pat.is_empty() || pat.starts_with('#') {
            continue;
        }
        let g = Glob::new(pat).with_context(|| format!("invalid exclude pattern: {pat}"))?;
        builder.add(g);
    }
    Ok(builder.build()?)
}

/// Walk `root` and produce a sorted manifest. The `.localsend-sync` directory
/// is always excluded even if no pattern covers it (it stores the receiver's
/// sync state and would create a feedback loop).
pub fn compute(
    root: &Path,
    excludes: &GlobSet,
    original_patterns: &[String],
    now_iso: &str,
) -> Result<Manifest> {
    let meta_root = std::fs::symlink_metadata(root)
        .with_context(|| format!("stat {}", root.display()))?;
    if !meta_root.is_dir() {
        anyhow::bail!("share root is not a directory: {}", root.display());
    }

    let mut entries: Vec<Entry> = Vec::new();
    for dent in WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| !is_excluded_abs(e.path(), root, excludes))
    {
        let dent = match dent {
            Ok(d) => d,
            Err(e) => {
                tracing::warn!("walkdir error: {e}");
                continue;
            }
        };
        if dent.path() == root {
            // The root itself is implicit, not an entry.
            continue;
        }
        let rel = match dent.path().strip_prefix(root) {
            Ok(p) => p,
            Err(_) => continue,
        };
        let rel_str = path_to_forward(rel);

        let meta = match dent.metadata() {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!("stat {}: {e}", dent.path().display());
                continue;
            }
        };

        let mode = mode_from_metadata(&meta);
        let mtime_unix = meta
            .modified()
            .ok()
            .and_then(|m| m.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let (size, sha256) = if meta.is_file() {
            let size = meta.len();
            let sha = match sha256_file(dent.path()) {
                Ok(s) => s,
                Err(e) => {
                    tracing::warn!("hash {}: {e}", dent.path().display());
                    continue;
                }
            };
            (size, sha)
        } else {
            (0, String::new())
        };

        entries.push(Entry {
            path: rel_str,
            size,
            mtime_unix,
            sha256,
            mode,
        });
    }

    entries.sort_by(|a, b| a.path.cmp(&b.path));

    Ok(Manifest {
        version: MANIFEST_VERSION,
        root: root.to_path_buf(),
        generated_at: now_iso.to_string(),
        excludes: original_patterns.to_vec(),
        entries,
    })
}

/// Compute the SHA-256 of a file as lowercase hex.
pub fn sha256_file(path: &Path) -> Result<String> {
    use std::io::Read;
    let mut f = std::fs::File::open(path).with_context(|| format!("open {}", path.display()))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = f
            .read(&mut buf)
            .with_context(|| format!("read {}", path.display()))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex_lower(hasher.finalize().as_slice()))
}

fn is_excluded_abs(abs: &Path, root: &Path, set: &GlobSet) -> bool {
    if abs == root {
        return false;
    }
    let rel = match abs.strip_prefix(root) {
        Ok(p) => p,
        Err(_) => return false,
    };
    let rel_str = path_to_forward(rel);
    // Always exclude the receiver's sync state directory.
    if rel_str == ".localsend-sync" || rel_str.starts_with(".localsend-sync/") {
        return true;
    }
    set.is_match(&rel_str)
}

fn path_to_forward(p: &Path) -> String {
    p.components()
        .map(|c| c.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("/")
}

fn mode_from_metadata(meta: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::MetadataExt;
    meta.mode()
}

fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

/// Current wall-clock time as ISO-8601 UTC. The dependency on the `time`
/// crate is kept out of this module so the sync feature compiles even when
/// the `time` feature is off.
pub fn now_iso() -> String {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(d) => format_iso8601_utc(d.as_secs() as i64),
        Err(_) => "1970-01-01T00:00:00Z".to_string(),
    }
}

fn format_iso8601_utc(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let secs_of_day = secs.rem_euclid(86_400);
    let hour = secs_of_day / 3600;
    let min = (secs_of_day % 3600) / 60;
    let sec = secs_of_day % 60;
    let (y, m, d) = civil_from_days(days);
    format!("{y:04}-{m:02}-{d:02}T{hour:02}:{min:02}:{sec:02}Z")
}

fn civil_from_days(z: i64) -> (i32, u32, u32) {
    // Howard Hinnant's days-from-civil algorithm (inverse).
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y as i32, m as u32, d as u32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    /// Create a unique temp dir under `target/tmp/sync-tests/`. Skips the test
    /// if the host filesystem does not let us create it.
    fn fresh_tmp(label: &str) -> Option<PathBuf> {
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let pid = std::process::id();
        let dir = std::env::temp_dir()
            .join("localsend-sync-tests")
            .join(format!("{label}-{pid}-{n}"));
        if fs::create_dir_all(&dir).is_err() {
            return None;
        }
        Some(dir)
    }

    fn write(p: &Path, body: &[u8]) {
        fs::write(p, body).unwrap();
    }

    fn entry<'a>(m: &'a Manifest, path: &str) -> &'a Entry {
        m.get(path).unwrap_or_else(|| panic!("missing entry {path}"))
    }

    #[test]
    fn compile_skips_blanks_and_comments() {
        let set = compile_excludes(["", "# a comment", "*.tmp"]).unwrap();
        assert!(set.is_match("foo.tmp"));
        assert!(!set.is_match("foo.txt"));
    }

    #[test]
    fn compile_rejects_invalid_glob() {
        assert!(compile_excludes(["[unterminated"]).is_err());
    }

    #[test]
    fn manifest_walks_and_sorts() {
        let Some(root) = fresh_tmp("walks") else {
            eprintln!("skip: cannot create temp dir");
            return;
        };
        write(&root.join("b.txt"), b"world");
        write(&root.join("a.txt"), b"hello");
        fs::create_dir(root.join("sub")).unwrap();
        write(&root.join("sub").join("c.txt"), b"!");

        let set = compile_excludes::<_, &str>([]).unwrap();
        let m = compute(&root, &set, &[], "2026-01-01T00:00:00Z").unwrap();

        // walkdir reports the directory itself as an entry, so we expect:
        // a.txt, b.txt, sub (dir), sub/c.txt = 4 entries.
        assert_eq!(m.entries.len(), 4);
        assert_eq!(m.entries[0].path, "a.txt");
        assert_eq!(m.entries[1].path, "b.txt");
        assert_eq!(m.entries[2].path, "sub");
        assert_eq!(m.entries[3].path, "sub/c.txt");
        assert!(entry(&m, "sub").is_dir());
        assert!(entry(&m, "sub/c.txt").is_file());

        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn manifest_applies_excludes() {
        let Some(root) = fresh_tmp("excl") else {
            return;
        };
        write(&root.join("keep.txt"), b"k");
        fs::create_dir(root.join("bak")).unwrap();
        write(&root.join("bak").join("drop.bin"), b"d");
        write(&root.join("note.tmp"), b"t");

        let set = compile_excludes(["bak/**", "*.tmp"]).unwrap();
        let m = compute(&root, &set, &["bak/**".into(), "*.tmp".into()], "t").unwrap();

        let paths: Vec<&str> = m.entries.iter().map(|e| e.path.as_str()).collect();
        assert!(paths.contains(&"keep.txt"));
        assert!(!paths.iter().any(|p| p.starts_with("bak/")));
        assert!(!paths.contains(&"note.tmp"));

        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn manifest_always_excludes_localsend_sync() {
        let Some(root) = fresh_tmp("state") else {
            return;
        };
        write(&root.join("real.txt"), b"x");
        fs::create_dir(root.join(".localsend-sync")).unwrap();
        write(
            &root.join(".localsend-sync").join("state.json"),
            b"{}",
        );

        let set = compile_excludes::<_, &str>([]).unwrap();
        let m = compute(&root, &set, &[], "t").unwrap();

        let paths: Vec<&str> = m.entries.iter().map(|e| e.path.as_str()).collect();
        assert_eq!(paths, vec!["real.txt"]);

        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn sha256_is_stable_and_lowercase() {
        let Some(root) = fresh_tmp("hash") else {
            return;
        };
        write(&root.join("f"), b"abc");
        let h = sha256_file(&root.join("f")).unwrap();
        // echo -n abc | sha256sum
        assert_eq!(
            h,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert!(h.chars().all(|c| !c.is_ascii_uppercase()));
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn iso8601_known_dates() {
        // 1970-01-01T00:00:00Z
        assert_eq!(format_iso8601_utc(0), "1970-01-01T00:00:00Z");
        // 2024-01-01T00:00:00Z = 1704067200
        assert_eq!(format_iso8601_utc(1_704_067_200), "2024-01-01T00:00:00Z");
        // 2000-02-29T00:00:00Z = 951782400 (leap day; 2000 is a leap year)
        assert_eq!(format_iso8601_utc(951_782_400), "2000-02-29T00:00:00Z");
        // 2025-12-31T23:59:59Z = 1767225599
        assert_eq!(format_iso8601_utc(1_767_225_599), "2025-12-31T23:59:59Z");
    }
}
