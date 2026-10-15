//! Receiver-side persistence for a sync session.
//!
//! The state file is written to `<receiver_root>/.localsend-sync/<share_id>/state.json`.
//! `.localsend-sync` is excluded from manifests by the `manifest` module so
//! the state file is never sent back to the sender.
//!
//! `save` is atomic: it stages into `state.json.tmp` and renames.

use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

const FILE_NAME: &str = "state.json";
const STATE_DIR: &str = ".localsend-sync";

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncState {
    /// Fingerprint of the sender's TLS client certificate. Used to detect
    /// "same share, different device" and refuse to apply a stale plan.
    pub peer_fingerprint: String,
    /// Human-friendly name of the share as advertised by the sender.
    pub share_name: String,
    /// Last successful sync timestamp (ISO-8601 UTC).
    pub last_sync_at: String,
    /// Lower-case hex SHA-256 of the remote manifest, for fast equality checks.
    pub last_remote_manifest_hash: String,
    /// Paths the user has marked as "always skip" or "always keep local".
    #[serde(default)]
    pub local_overrides: LocalOverrides,
    /// Paths the receiver knows about from the last successful sync, used to
    /// distinguish "new" from "remotely/locally deleted" in the diff.
    #[serde(default)]
    pub known_paths: HashSet<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalOverrides {
    /// Paths that the user always wants skipped on subsequent syncs.
    #[serde(default)]
    pub skipped: HashSet<String>,
    /// Paths the user has explicitly resolved (so the next diff does not
    /// re-prompt for them).
    #[serde(default)]
    pub resolved: HashSet<String>,
}

/// Canonical location of a share's state file.
pub fn state_path(receiver_root: &Path, share_id: &str) -> PathBuf {
    receiver_root.join(STATE_DIR).join(share_id).join(FILE_NAME)
}

/// Load the state file, or return `None` if it does not exist.
pub fn load(receiver_root: &Path, share_id: &str) -> anyhow::Result<Option<SyncState>> {
    let p = state_path(receiver_root, share_id);
    if !p.exists() {
        return Ok(None);
    }
    let bytes = std::fs::read(&p)?;
    let st: SyncState = serde_json::from_slice(&bytes)?;
    Ok(Some(st))
}

/// Save the state atomically (write to `state.json.tmp`, then rename).
pub fn save(receiver_root: &Path, share_id: &str, state: &SyncState) -> anyhow::Result<()> {
    let p = state_path(receiver_root, share_id);
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = p.with_extension("json.tmp");
    let bytes = serde_json::to_vec_pretty(state)?;
    std::fs::write(&tmp, &bytes)?;
    std::fs::rename(&tmp, &p)?;
    Ok(())
}

/// Remove the state file. Returns `true` if a file was removed.
pub fn clear(receiver_root: &Path, share_id: &str) -> anyhow::Result<bool> {
    let p = state_path(receiver_root, share_id);
    if !p.exists() {
        return Ok(false);
    }
    std::fs::remove_file(&p)?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn fresh_tmp(label: &str) -> Option<PathBuf> {
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let pid = std::process::id();
        let dir = std::env::temp_dir()
            .join("localsend-sync-state-tests")
            .join(format!("{label}-{pid}-{n}"));
        if fs::create_dir_all(&dir).is_err() {
            return None;
        }
        Some(dir)
    }

    fn sample_state() -> SyncState {
        let mut s = SyncState {
            peer_fingerprint: "ABCD".into(),
            share_name: "dir1".into(),
            last_sync_at: "2026-08-26T10:00:00Z".into(),
            last_remote_manifest_hash: "deadbeef".into(),
            ..Default::default()
        };
        s.known_paths.insert("a.txt".into());
        s.known_paths.insert("sub/b.txt".into());
        s.local_overrides
            .skipped
            .insert("ignored.txt".into());
        s
    }

    #[test]
    fn roundtrip_save_load() {
        let Some(root) = fresh_tmp("rt") else {
            return;
        };
        let s = sample_state();
        save(&root, "share-1", &s).unwrap();
        let loaded = load(&root, "share-1").unwrap().unwrap();
        assert_eq!(loaded, s);
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn load_returns_none_when_absent() {
        let Some(root) = fresh_tmp("none") else {
            return;
        };
        assert!(load(&root, "nope").unwrap().is_none());
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn save_creates_parent_directories() {
        let Some(root) = fresh_tmp("mkdir") else {
            return;
        };
        save(&root, "deeply/nested/share", &sample_state()).unwrap();
        let p = state_path(&root, "deeply/nested/share");
        assert!(p.exists());
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn save_is_atomic_via_tmp_rename() {
        let Some(root) = fresh_tmp("atomic") else {
            return;
        };
        save(&root, "share", &sample_state()).unwrap();
        let p = state_path(&root, "share");
        // After a successful save, no .tmp should remain.
        let tmp = p.with_extension("json.tmp");
        assert!(!tmp.exists());
        assert!(p.exists());
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn clear_removes_existing_file() {
        let Some(root) = fresh_tmp("clear") else {
            return;
        };
        save(&root, "share", &sample_state()).unwrap();
        assert!(clear(&root, "share").unwrap());
        assert!(!clear(&root, "share").unwrap());
        assert!(load(&root, "share").unwrap().is_none());
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn state_path_layout() {
        let root = PathBuf::from("/mirror");
        assert_eq!(
            state_path(&root, "abc"),
            PathBuf::from("/mirror/.localsend-sync/abc/state.json")
        );
    }
}
