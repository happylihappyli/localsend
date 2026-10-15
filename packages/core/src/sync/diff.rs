//! Compute a [`Plan`] from two manifests and the receiver's previous sync state.
//!
//! Inputs:
//! - `remote`: manifest of the share as published by the sender.
//! - `local`: manifest of the receiver's mirror of the share.
//! - `previous_paths`: paths the receiver knew about in the last successful
//!   sync, used to distinguish "new" from "remotely deleted" / "locally deleted".
//!
//! See `support/sync_design.md` §4 for the algorithm.

use crate::sync::{Conflict, Entry, Manifest, Plan, Skip, SkipReason, Transfer, PLAN_VERSION};
use std::collections::{HashMap, HashSet};

/// Compute the plan. `now` is an ISO-8601 UTC string that will be written
/// into `Plan.generated_at` (caller-provided to make tests deterministic).
pub fn compute(remote: &Manifest, local: &Manifest, previous_paths: &[String], now: &str) -> Plan {
    let local_by_path: HashMap<&str, &Entry> = local
        .entries
        .iter()
        .map(|e| (e.path.as_str(), e))
        .collect();
    let prev: HashSet<&str> = previous_paths.iter().map(|s| s.as_str()).collect();

    let mut downloads: Vec<Transfer> = Vec::new();
    let mut uploads: Vec<Transfer> = Vec::new();
    let mut conflicts: Vec<Conflict> = Vec::new();
    let mut skips: Vec<Skip> = Vec::new();

    for r in &remote.entries {
        if !r.is_file() {
            continue;
        }
        match local_by_path.get(r.path.as_str()) {
            None => {
                if prev.contains(r.path.as_str()) {
                    skips.push(Skip {
                        path: r.path.clone(),
                        reason: SkipReason::LocallyDeleted,
                    });
                } else {
                    downloads.push(Transfer {
                        path: r.path.clone(),
                        size: r.size,
                        sha256: r.sha256.clone(),
                    });
                }
            }
            Some(l) if !l.is_file() => {
                // Sender has a file where the receiver has a dir/symlink.
                // v1 does not delete the receiver side; we treat the remote
                // file as new and skip it so the user can resolve manually.
                skips.push(Skip {
                    path: r.path.clone(),
                    reason: SkipReason::TypeMismatch,
                });
            }
            Some(l) if l.sha256 == r.sha256 => {
                if l.mtime_unix == r.mtime_unix {
                    skips.push(Skip {
                        path: r.path.clone(),
                        reason: SkipReason::Unchanged,
                    });
                } else {
                    skips.push(Skip {
                        path: r.path.clone(),
                        reason: SkipReason::TouchOnly,
                    });
                }
            }
            Some(l) => {
                // sha256 differs. v1 surfaces this as a conflict; the user
                // picks local/remote/both. The mtime ordering is recorded
                // in the conflict struct so the UI can suggest a default.
                conflicts.push(Conflict {
                    path: r.path.clone(),
                    local_mtime_unix: l.mtime_unix,
                    local_sha256: l.sha256.clone(),
                    local_size: l.size,
                    remote_mtime_unix: r.mtime_unix,
                    remote_sha256: r.sha256.clone(),
                    remote_size: r.size,
                });
            }
        }
    }

    // Local files that are not in remote: either newly created locally, or
    // remotely deleted (v1 keeps the local copy untouched).
    for l in &local.entries {
        if !l.is_file() {
            continue;
        }
        if remote.contains(&l.path) {
            continue;
        }
        if prev.contains(l.path.as_str()) {
            skips.push(Skip {
                path: l.path.clone(),
                reason: SkipReason::RemotelyDeleted,
            });
            continue;
        }
        uploads.push(Transfer {
            path: l.path.clone(),
            size: l.size,
            sha256: l.sha256.clone(),
        });
    }

    // Deterministic ordering for stable display.
    downloads.sort_by(|a, b| a.path.cmp(&b.path));
    uploads.sort_by(|a, b| a.path.cmp(&b.path));
    conflicts.sort_by(|a, b| a.path.cmp(&b.path));
    skips.sort_by(|a, b| a.path.cmp(&b.path));

    Plan {
        version: PLAN_VERSION,
        generated_at: now.to_string(),
        downloads,
        uploads,
        conflicts,
        skips,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sync::manifest::now_iso;

    fn file(path: &str, sha: &str, mtime: i64) -> Entry {
        Entry {
            path: path.into(),
            size: sha.len() as u64,
            mtime_unix: mtime,
            sha256: sha.into(),
            mode: 0o100644,
        }
    }

    fn manifest(entries: Vec<Entry>) -> Manifest {
        Manifest {
            version: 1,
            root: PathBuf::from("/x"),
            generated_at: String::new(),
            excludes: vec![],
            entries,
        }
    }

    use std::path::PathBuf;

    fn run(remote: Manifest, local: Manifest, prev: &[&str]) -> Plan {
        let prev: Vec<String> = prev.iter().map(|s| s.to_string()).collect();
        compute(&remote, &local, &prev, &now_iso())
    }

    #[test]
    fn empty_local_means_all_downloads() {
        let remote = manifest(vec![file("a.txt", "aaa", 1), file("b.txt", "bbb", 1)]);
        let local = manifest(vec![]);
        let plan = run(remote, local, &[]);
        assert_eq!(plan.download_count(), 2);
        assert_eq!(plan.upload_count(), 0);
        assert_eq!(plan.conflict_count(), 0);
        assert_eq!(plan.downloads[0].path, "a.txt");
        assert_eq!(plan.downloads[1].path, "b.txt");
    }

    #[test]
    fn empty_remote_means_all_uploads_when_new_locally() {
        let remote = manifest(vec![]);
        let local = manifest(vec![file("a.txt", "aaa", 1)]);
        let plan = run(remote, local, &[]);
        assert_eq!(plan.download_count(), 0);
        assert_eq!(plan.upload_count(), 1);
        assert_eq!(plan.uploads[0].path, "a.txt");
    }

    #[test]
    fn identical_files_are_skipped_unchanged() {
        let f = file("a.txt", "aaa", 100);
        let remote = manifest(vec![f.clone()]);
        let local = manifest(vec![f]);
        let plan = run(remote, local, &[]);
        assert_eq!(plan.download_count(), 0);
        assert_eq!(plan.conflict_count(), 0);
        assert_eq!(plan.skips.len(), 1);
        assert_eq!(plan.skips[0].reason, SkipReason::Unchanged);
    }

    #[test]
    fn same_sha_different_mtime_is_touch_only() {
        let f1 = file("a.txt", "aaa", 100);
        let f2 = file("a.txt", "aaa", 200);
        let plan = run(manifest(vec![f1]), manifest(vec![f2]), &[]);
        assert_eq!(plan.skips.len(), 1);
        assert_eq!(plan.skips[0].reason, SkipReason::TouchOnly);
    }

    #[test]
    fn different_sha_is_a_conflict() {
        let plan = run(
            manifest(vec![file("a.txt", "remote-sha", 200)]),
            manifest(vec![file("a.txt", "local-sha", 100)]),
            &[],
        );
        assert_eq!(plan.conflict_count(), 1);
        let c = &plan.conflicts[0];
        assert_eq!(c.path, "a.txt");
        assert_eq!(c.local_sha256, "local-sha");
        assert_eq!(c.remote_sha256, "remote-sha");
    }

    #[test]
    fn previously_synced_then_locally_deleted_skips() {
        let plan = run(
            manifest(vec![file("a.txt", "aaa", 1)]),
            manifest(vec![]),
            &["a.txt"],
        );
        assert_eq!(plan.download_count(), 0);
        assert_eq!(plan.skips.len(), 1);
        assert_eq!(plan.skips[0].reason, SkipReason::LocallyDeleted);
    }

    #[test]
    fn previously_synced_then_remotely_deleted_keeps_local() {
        let plan = run(
            manifest(vec![]),
            manifest(vec![file("a.txt", "aaa", 1)]),
            &["a.txt"],
        );
        assert_eq!(plan.upload_count(), 0);
        assert_eq!(plan.skips.len(), 1);
        assert_eq!(plan.skips[0].reason, SkipReason::RemotelyDeleted);
    }

    #[test]
    fn directories_are_ignored_in_transfer_logic() {
        let mut dir_entry = file("sub", "", 1);
        dir_entry.mode = 0o040755;
        let mut remote = manifest(vec![file("sub/a.txt", "aaa", 1)]);
        remote.entries.push(dir_entry.clone());
        let local = manifest(vec![file("sub/a.txt", "aaa", 1)]);
        let plan = run(remote, local, &[]);
        // The dir entry is not a file, so it must not appear in uploads or
        // be treated as a conflict.
        assert_eq!(plan.download_count(), 0);
        assert_eq!(plan.conflict_count(), 0);
        assert_eq!(plan.skips.len(), 1);
    }

    #[test]
    fn type_mismatch_is_reported_as_skip() {
        let mut dir = file("a.txt", "", 1);
        dir.mode = 0o040755;
        let plan = run(
            manifest(vec![file("a.txt", "aaa", 1)]),
            manifest(vec![dir]),
            &[],
        );
        assert_eq!(plan.download_count(), 0);
        assert_eq!(plan.conflict_count(), 0);
        assert_eq!(plan.skips.len(), 1);
        assert_eq!(plan.skips[0].reason, SkipReason::TypeMismatch);
    }

    #[test]
    fn plan_is_stably_ordered() {
        let remote = manifest(vec![
            file("z.txt", "z", 1),
            file("a.txt", "a", 1),
            file("m.txt", "m", 1),
        ]);
        let local = manifest(vec![]);
        let plan = run(remote, local, &[]);
        let paths: Vec<&str> = plan.downloads.iter().map(|t| t.path.as_str()).collect();
        assert_eq!(paths, vec!["a.txt", "m.txt", "z.txt"]);
    }
}
