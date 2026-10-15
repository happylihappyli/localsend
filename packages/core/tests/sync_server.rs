#![cfg(feature = "full")]

//! End-to-end tests for the directory-sync HTTP endpoints.
//!
//! The tests start a v2 server with a single share rooted at a temp directory,
//! then drive each endpoint with `reqwest` and check the wire format. The unit
//! tests inside `src/sync/{manifest,diff,state,http}.rs` cover the algorithms
//! in isolation; this file is about the bytes that actually go over HTTP.

use localsend::http::server::v2::ServerEventV2;
use localsend::http::server::web::WebConfig;
use localsend::http::server::{start_with_port, ServerConfigV2};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::DeviceType;
use localsend::sync::http::{ShareInfo, SyncShareConfig, TreeEntry};
use localsend::sync::manifest::compile_excludes;
use localsend::sync::Manifest;
use serde_json::json;
use std::path::PathBuf;
use tokio::sync::{mpsc, oneshot};

/// Set up a share directory with three files and one that should be excluded
/// by the share's `*.bak` pattern. Returns the share root path.
async fn setup_share() -> PathBuf {
    let root = std::env::temp_dir().join(format!("localsend-sync-test-{}", uuid::Uuid::new_v4()));
    tokio::fs::create_dir_all(&root).await.unwrap();
    tokio::fs::write(root.join("readme.txt"), b"hello world\n")
        .await
        .unwrap();
    tokio::fs::write(root.join("a.bin"), b"AAA").await.unwrap();
    tokio::fs::write(root.join("ignore.bak"), b"not synced")
        .await
        .unwrap();
    tokio::fs::write(root.join("keep.txt"), b"keep me").await.unwrap();
    root
}

/// Spawns a server with one share that uses the `*.bak` exclude pattern,
/// matching the layout produced by [`setup_share`]. Returns the bound port.
async fn start_test_server_with_share(
    share_id: &str,
    share_name: &str,
    root: PathBuf,
) -> (u16, oneshot::Sender<()>) {
    let _ = tracing_subscriber::fmt().with_test_writer().try_init();

    // The v2 server requires an event channel; we never read it, but a
    // minimal capacity keeps the drop guard from blocking the server.
    let (event_tx, _event_rx) = mpsc::channel::<ServerEventV2>(16);
    let (stop_tx, stop_rx) = oneshot::channel();

    let handle = start_with_port(
        0,
        None, // plain HTTP; sync routes don't need TLS
        ClientInfo {
            alias: "Sync Sender".to_string(),
            version: "2.0".to_string(),
            device_model: None,
            device_type: Some(DeviceType::Headless),
            token: "sender-fingerprint".to_string(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
            sync_shares: vec![SyncShareConfig {
                id: share_id.to_string(),
                name: share_name.to_string(),
                root,
                excludes: vec!["*.bak".to_string()],
            }],
        }),
        WebConfig::default(),
        stop_rx,
    )
    .await
    .expect("Failed to start sync test server");

    (handle.port(), stop_tx)
}

fn base_url(port: u16) -> String {
    format!("http://127.0.0.1:{port}")
}

#[tokio::test]
async fn list_shares_endpoint_returns_share_metadata() {
    let share_root = setup_share().await;
    let (port, _stop) =
        start_test_server_with_share("my-share", "My Share", share_root.clone()).await;

    let shares: Vec<ShareInfo> = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/",
        base_url(port)
    ))
    .await
    .unwrap()
    .error_for_status()
    .unwrap()
    .json()
    .await
    .unwrap();

    assert_eq!(shares.len(), 1);
    assert_eq!(shares[0].id, "my-share");
    assert_eq!(shares[0].name, "My Share");
}

#[tokio::test]
async fn list_shares_endpoint_empty_when_no_shares() {
    let (event_tx, _event_rx) = mpsc::channel::<ServerEventV2>(16);
    let (stop_tx, stop_rx) = oneshot::channel();
    let handle = start_with_port(
        0,
        None,
        ClientInfo {
            alias: "Empty".to_string(),
            version: "2.0".to_string(),
            device_model: None,
            device_type: Some(DeviceType::Headless),
            token: "empty-fp".to_string(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
            sync_shares: vec![],
        }),
        WebConfig::default(),
        stop_rx,
    )
    .await
    .expect("Failed to start server with no shares");
    let port = handle.port();

    let shares: Vec<ShareInfo> = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/",
        base_url(port)
    ))
    .await
    .unwrap()
    .error_for_status()
    .unwrap()
    .json()
    .await
    .unwrap();
    assert!(shares.is_empty());
    let _ = stop_tx.send(());
}

#[tokio::test]
async fn list_shares_endpoint_rejects_non_get() {
    let share_root = setup_share().await;
    let (port, _stop) =
        start_test_server_with_share("my-share", "My Share", share_root.clone()).await;
    let res = localsend::reqwest::Client::new()
        .post(format!("{}/api/localsend/sync/", base_url(port)))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status().as_u16(), 404);
}

#[tokio::test]
async fn manifest_endpoint_returns_entries() {
    let share_root = setup_share().await;
    let (port, _stop) =
        start_test_server_with_share("my-share", "My Share", share_root.clone()).await;

    let manifest: Manifest = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/my-share/manifest",
        base_url(port)
    ))
    .await
    .unwrap()
    .error_for_status()
    .unwrap()
    .json()
    .await
    .unwrap();

    assert_eq!(manifest.version, 1);
    // excludes echoed back so the receiver can show them
    assert_eq!(manifest.excludes, vec!["*.bak".to_string()]);
    let paths: Vec<&str> = manifest.entries.iter().map(|e| e.path.as_str()).collect();
    assert!(paths.contains(&"a.bin"));
    assert!(paths.contains(&"keep.txt"));
    assert!(paths.contains(&"readme.txt"));
    // The `*.bak` pattern removes the `bak/ignored.bak` file from the share,
    // so the manifest must not contain any path ending in `.bak`.
    assert!(paths.iter().all(|p| !p.ends_with(".bak")));
    // the bak file content
    assert_eq!(manifest.get("a.bin").unwrap().size, 3);
}

#[tokio::test]
async fn manifest_returns_404_for_unknown_share() {
    let share_root = setup_share().await;
    let (port, _stop) = start_test_server_with_share("real", "Real", share_root).await;

    let res = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/nonexistent/manifest",
        base_url(port)
    ))
    .await
    .unwrap();
    assert_eq!(res.status().as_u16(), 404);
}

#[tokio::test]
async fn tree_endpoint_lists_root() {
    let share_root = setup_share().await;
    let (port, _stop) =
        start_test_server_with_share("my-share", "My Share", share_root.clone()).await;

    let entries: Vec<TreeEntry> = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/my-share/tree",
        base_url(port)
    ))
    .await
    .unwrap()
    .error_for_status()
    .unwrap()
    .json()
    .await
    .unwrap();

    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    assert!(names.contains(&"a.bin"));
    assert!(names.contains(&"readme.txt"));
    assert!(names.contains(&"keep.txt"));
    // `ignore.bak` matches the `*.bak` exclude pattern and is filtered out.
    assert!(!names.contains(&"ignore.bak"));
}

#[tokio::test]
async fn tree_endpoint_rejects_parent_traversal() {
    let share_root = setup_share().await;
    let (port, _stop) = start_test_server_with_share("my-share", "My Share", share_root).await;

    let res = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/my-share/tree?path=../etc",
        base_url(port)
    ))
    .await
    .unwrap();
    assert_eq!(res.status().as_u16(), 400);
}

#[tokio::test]
async fn file_get_returns_bytes() {
    let share_root = setup_share().await;
    let (port, _stop) =
        start_test_server_with_share("my-share", "My Share", share_root.clone()).await;

    let res = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/my-share/file?path=a.bin",
        base_url(port)
    ))
    .await
    .unwrap()
    .error_for_status()
    .unwrap();
    let bytes = res.bytes().await.unwrap();
    assert_eq!(bytes.as_ref(), b"AAA");
}

#[tokio::test]
async fn file_get_rejects_parent_traversal() {
    let share_root = setup_share().await;
    let (port, _stop) = start_test_server_with_share("my-share", "My Share", share_root).await;

    let res = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/my-share/file?path=..%2F..%2Fetc%2Fpasswd",
        base_url(port)
    ))
    .await
    .unwrap();
    assert_eq!(res.status().as_u16(), 400);
}

#[tokio::test]
async fn file_get_returns_404_for_missing_file() {
    let share_root = setup_share().await;
    let (port, _stop) = start_test_server_with_share("my-share", "My Share", share_root).await;

    let res = localsend::reqwest::get(format!(
        "{}/api/localsend/sync/my-share/file?path=does-not-exist.txt",
        base_url(port)
    ))
    .await
    .unwrap();
    assert_eq!(res.status().as_u16(), 404);
}

#[tokio::test]
async fn plan_endpoint_reports_downloads() {
    let share_root = setup_share().await;
    let (port, _stop) =
        start_test_server_with_share("my-share", "My Share", share_root).await;

    // Empty local manifest + empty previous_paths -> everything is a download.
    let body = json!({
        "previous_paths": [],
        "local": {
            "version": 1,
            "root": "/tmp/empty",
            "generated_at": "1970-01-01T00:00:00Z",
            "excludes": [],
            "entries": []
        }
    });
    let client = localsend::reqwest::Client::new();
    let res = client
        .post(format!(
            "{}/api/localsend/sync/my-share/plan",
            base_url(port)
        ))
        .json(&body)
        .send()
        .await
        .unwrap();
    assert!(res.status().is_success());
    let plan: localsend::sync::Plan = res.json().await.unwrap();
    let download_paths: Vec<&str> = plan.downloads.iter().map(|t| t.path.as_str()).collect();
    // The `*.bak` pattern removes the `ignore.bak` file from the share, so
    // the plan must not list any path ending in `.bak` for download.
    assert!(download_paths.contains(&"a.bin"));
    assert!(download_paths.contains(&"readme.txt"));
    assert!(download_paths.iter().all(|p| !p.ends_with(".bak")));
    // No local files, so no conflicts.
    assert!(plan.conflicts.is_empty());
}

#[tokio::test]
async fn plan_endpoint_detects_conflict_on_modified_local_copy() {
    let share_root = setup_share().await;
    let (port, _stop) =
        start_test_server_with_share("my-share", "My Share", share_root.clone()).await;

    // Pretend the receiver has the same file but with different content.
    let mut local: Manifest = localsend::sync::manifest::compute(
        &share_root,
        &compile_excludes(std::iter::empty::<&str>()).unwrap(),
        &[],
        "1970-01-01T00:00:00Z",
    )
    .unwrap();
    // Mutate the local sha256 of one entry to force a conflict.
    let entry = local.entries.iter_mut().find(|e| e.path == "a.bin").unwrap();
    entry.sha256 = "deadbeef".to_string();

    let body = json!({
        "previous_paths": ["a.bin"],
        "local": local,
    });
    let client = localsend::reqwest::Client::new();
    let plan: localsend::sync::Plan = client
        .post(format!(
            "{}/api/localsend/sync/my-share/plan",
            base_url(port)
        ))
        .json(&body)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    let conflicted: Vec<&str> = plan.conflicts.iter().map(|c| c.path.as_str()).collect();
    assert!(conflicted.contains(&"a.bin"));
}

#[tokio::test]
async fn plan_endpoint_marks_unchanged() {
    let share_root = setup_share().await;
    let (port, _stop) =
        start_test_server_with_share("my-share", "My Share", share_root.clone()).await;

    // Local manifest that matches the share exactly -> everything is "unchanged".
    let local: Manifest = localsend::sync::manifest::compute(
        &share_root,
        &compile_excludes(std::iter::empty::<&str>()).unwrap(),
        &[],
        "1970-01-01T00:00:00Z",
    )
    .unwrap();
    let previous: Vec<String> = local.entries.iter().map(|e| e.path.clone()).collect();
    let body = json!({
        "previous_paths": previous,
        "local": local,
    });
    let client = localsend::reqwest::Client::new();
    let plan: localsend::sync::Plan = client
        .post(format!(
            "{}/api/localsend/sync/my-share/plan",
            base_url(port)
        ))
        .json(&body)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(plan.downloads.is_empty());
    assert!(plan.conflicts.is_empty());
    // The skip list must contain every sync'd path with reason `unchanged`.
    let unchanged: Vec<&str> = plan
        .skips
        .iter()
        .filter(|s| matches!(s.reason, localsend::sync::SkipReason::Unchanged))
        .map(|s| s.path.as_str())
        .collect();
    assert!(unchanged.contains(&"a.bin"));
    assert!(unchanged.contains(&"readme.txt"));
    assert!(unchanged.contains(&"keep.txt"));
}

#[tokio::test]
async fn file_put_writes_into_share() {
    let share_root = setup_share().await;
    let (port, _stop) = start_test_server_with_share("my-share", "My Share", share_root).await;

    let client = localsend::reqwest::Client::new();
    let payload = b"hello from the receiver";
    let res = client
        .put(format!(
            "{}/api/localsend/sync/my-share/file?path=uploaded.txt",
            base_url(port)
        ))
        .body(payload.to_vec())
        .send()
        .await
        .unwrap();
    assert!(res.status().is_success());
    let body: serde_json::Value = res.json().await.unwrap();
    let staged: String = body["staged_path"].as_str().unwrap().to_string();
    assert!(staged.contains(".localsend-sync-upload-"));
    let on_disk = std::fs::read(&staged).unwrap();
    assert_eq!(on_disk, payload);
    let _ = std::fs::remove_file(&staged);
}

#[tokio::test]
async fn disabled_when_no_shares() {
    // No sync_shares -> sync routes return 404.
    let _ = tracing_subscriber::fmt().with_test_writer().try_init();
    let (event_tx, _event_rx) = mpsc::channel::<ServerEventV2>(16);
    let (stop_tx, stop_rx) = oneshot::channel();
    let handle = start_with_port(
        0,
        None,
        ClientInfo {
            alias: "Empty".to_string(),
            version: "2.0".to_string(),
            device_model: None,
            device_type: Some(DeviceType::Headless),
            token: "fp".to_string(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
            sync_shares: vec![],
        }),
        WebConfig::default(),
        stop_rx,
    )
    .await
    .unwrap();
    let port = handle.port();
    let _stop_tx = stop_tx;
    let res = localsend::reqwest::get(format!(
        "http://127.0.0.1:{port}/api/localsend/sync/any/manifest"
    ))
    .await
    .unwrap();
    assert_eq!(res.status().as_u16(), 404);
}
