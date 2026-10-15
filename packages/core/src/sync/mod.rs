//! Directory sync: manifest computation, diff, and receiver-side state.
//!
//! See `support/sync_design.md` for the protocol-level design. The HTTP
//! endpoints that serve these types are in [`http`].

pub mod diff;
#[cfg(feature = "http")]
pub mod http;
pub mod manifest;
pub mod state;

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Format version of the on-the-wire manifest. Bump when the layout changes
/// in a way that older receivers must understand to keep working.
pub const MANIFEST_VERSION: u32 = 1;

/// Format version of the on-the-wire plan.
pub const PLAN_VERSION: u32 = 1;

/// One file or directory entry inside the shared tree.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    /// Path relative to the share root, using forward slashes.
    pub path: String,
    /// File size in bytes. `0` for directories and non-regular entries.
    pub size: u64,
    /// Modification time as Unix seconds.
    pub mtime_unix: i64,
    /// Lower-case hex SHA-256 of the file contents. Empty for non-regular entries.
    pub sha256: String,
    /// Unix mode bits (regular files, directories, symlinks).
    pub mode: u32,
}

impl Entry {
    /// Regular file (the only kind that is actually transferred in v1).
    pub fn is_file(&self) -> bool {
        (self.mode & 0o170000) == 0o100000
    }

    /// Directory (used to preserve tree structure on the receiver).
    pub fn is_dir(&self) -> bool {
        (self.mode & 0o170000) == 0o040000
    }

    /// Symbolic link.
    pub fn is_symlink(&self) -> bool {
        (self.mode & 0o170000) == 0o120000
    }
}

/// Manifest of a shared directory, sorted by path.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub version: u32,
    /// Absolute path of the share root, used for error messages only.
    pub root: PathBuf,
    /// ISO-8601 UTC timestamp the manifest was generated.
    pub generated_at: String,
    /// Compiled exclude patterns (gitignore subset). Echoed so the receiver
    /// can display them in the UI.
    pub excludes: Vec<String>,
    /// Sorted by `path` ascending.
    pub entries: Vec<Entry>,
}

impl Manifest {
    /// Lookup by path. Returns `None` if absent.
    pub fn get(&self, path: &str) -> Option<&Entry> {
        self.entries
            .binary_search_by(|e| e.path.as_str().cmp(path))
            .ok()
            .map(|i| &self.entries[i])
    }

    /// True if the manifest contains an entry with the given path.
    pub fn contains(&self, path: &str) -> bool {
        self.get(path).is_some()
    }
}

/// One side of a conflict, with both local and remote metadata.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Conflict {
    pub path: String,
    pub local_mtime_unix: i64,
    pub local_sha256: String,
    pub local_size: u64,
    pub remote_mtime_unix: i64,
    pub remote_sha256: String,
    pub remote_size: u64,
}

/// A file that needs to be transferred (download or upload).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Transfer {
    pub path: String,
    pub size: u64,
    pub sha256: String,
}

/// Reason a file was left alone by the diff.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SkipReason {
    /// Identical mtime and sha256 on both sides.
    Unchanged,
    /// Same sha256 but mtime differs (file was touched without content change).
    TouchOnly,
    /// Hit an exclude pattern.
    Excluded,
    /// Was previously synced but has since been deleted on the receiver (v1
    /// does not propagate remote deletes; the file is kept untouched).
    LocallyDeleted,
    /// Was previously synced but the sender no longer has it (v1 keeps the
    /// local copy; the file is left as-is).
    RemotelyDeleted,
    /// Receiver has a directory where the sender has a file (or vice versa).
    TypeMismatch,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Skip {
    pub path: String,
    pub reason: SkipReason,
}

/// Diff result: what to download, upload, skip, and what the user has to decide.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Plan {
    pub version: u32,
    pub generated_at: String,
    pub downloads: Vec<Transfer>,
    pub uploads: Vec<Transfer>,
    pub conflicts: Vec<Conflict>,
    pub skips: Vec<Skip>,
}

impl Plan {
    /// Total number of files the receiver needs to fetch.
    pub fn download_count(&self) -> usize {
        self.downloads.len()
    }

    /// Total number of files the receiver would push back (v1 may not ship this).
    pub fn upload_count(&self) -> usize {
        self.uploads.len()
    }

    /// Number of files the user must resolve.
    pub fn conflict_count(&self) -> usize {
        self.conflicts.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entry_kind_detection() {
        let file = Entry {
            path: "a".into(),
            size: 0,
            mtime_unix: 0,
            sha256: String::new(),
            mode: 0o100644,
        };
        let dir = Entry {
            mode: 0o040755,
            ..file.clone()
        };
        let link = Entry {
            mode: 0o120777,
            ..file.clone()
        };
        assert!(file.is_file());
        assert!(!file.is_dir());
        assert!(!file.is_symlink());
        assert!(dir.is_dir());
        assert!(!dir.is_file());
        assert!(link.is_symlink());
    }

    #[test]
    fn manifest_lookup() {
        let m = Manifest {
            version: 1,
            root: PathBuf::from("/x"),
            generated_at: String::new(),
            excludes: vec![],
            entries: vec![
                Entry {
                    path: "a".into(),
                    size: 1,
                    mtime_unix: 0,
                    sha256: String::new(),
                    mode: 0o100644,
                },
                Entry {
                    path: "b".into(),
                    size: 2,
                    mtime_unix: 0,
                    sha256: String::new(),
                    mode: 0o100644,
                },
            ],
        };
        assert_eq!(m.get("a").unwrap().size, 1);
        assert_eq!(m.get("b").unwrap().size, 2);
        assert!(m.get("c").is_none());
        assert!(m.contains("a"));
        assert!(!m.contains("c"));
    }

    #[test]
    fn plan_counters() {
        let p = Plan {
            version: 1,
            generated_at: String::new(),
            downloads: vec![Transfer {
                path: "x".into(),
                size: 0,
                sha256: String::new(),
            }],
            uploads: vec![],
            conflicts: vec![],
            skips: vec![],
        };
        assert_eq!(p.download_count(), 1);
        assert_eq!(p.upload_count(), 0);
        assert_eq!(p.conflict_count(), 0);
    }
}
