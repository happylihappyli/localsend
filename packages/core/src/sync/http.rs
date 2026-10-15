//! HTTP endpoints for the directory sync protocol.
//!
//! See `support/sync_design.md` §3.2 for the protocol spec. Routes (relative
//! to the server root):
//!
//! - `GET  /api/localsend/sync/{share_id}/manifest`     -> [`Manifest`] JSON
//! - `GET  /api/localsend/sync/{share_id}/tree?path=...` -> [`TreeEntry`] JSON list
//! - `POST /api/localsend/sync/{share_id}/plan`          -> [`Plan`] JSON
//! - `GET  /api/localsend/sync/{share_id}/file?path=...` -> file body
//! - `PUT  /api/localsend/sync/{share_id}/file?path=...` -> receive file (v1 stub)

use super::diff;
use super::manifest;
use super::Manifest;
use crate::http::server::common::error::AppError;
use crate::http::server::common::response::{self, BoxedBody};
use crate::http::server::RequestClientInfo;
use bytes::Bytes;
use futures_util::StreamExt;
use globset::GlobSet;
use http_body_util::{BodyExt, StreamBody};
use hyper::body::{Frame, Incoming};
use hyper::header::{CONTENT_LENGTH, CONTENT_TYPE, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Component, Path, PathBuf};
use tokio_util::io::ReaderStream;

/// Public configuration for one share on the sender side. Constructed by the
/// application and passed in via [`ServerConfigV2::sync_shares`](crate::http::server::ServerConfigV2).
#[derive(Debug, Clone)]
pub struct SyncShareConfig {
    /// Stable identifier used in URLs and in the receiver's state file.
    pub id: String,
    /// Human-friendly name displayed in the receiver UI.
    pub name: String,
    /// Absolute path to the shared directory.
    pub root: PathBuf,
    /// Gitignore-style exclude patterns. Forward slashes only.
    pub excludes: Vec<String>,
}

/// Runtime state for the sync HTTP endpoints. `compiled_excludes` is the
/// precompiled globset cache keyed by share id; invalid patterns are dropped
/// with a warning so one bad share does not break the whole server.
pub(crate) struct SyncHttpState {
    pub shares: Vec<SyncShareConfig>,
    pub compiled_excludes: HashMap<String, GlobSet>,
}

impl SyncHttpState {
    pub(crate) fn new(shares: Vec<SyncShareConfig>) -> Self {
        let mut compiled = HashMap::new();
        for s in &shares {
            match manifest::compile_excludes(s.excludes.iter().map(String::as_str)) {
                Ok(set) => {
                    compiled.insert(s.id.clone(), set);
                }
                Err(err) => {
                    tracing::warn!(
                        "ignoring share {}: invalid exclude pattern: {err:#}",
                        s.id
                    );
                }
            }
        }
        Self {
            shares,
            compiled_excludes: compiled,
        }
    }

    pub(crate) fn lookup(&self, share_id: &str) -> Option<(&SyncShareConfig, &GlobSet)> {
        let share = self.shares.iter().find(|s| s.id == share_id)?;
        let set = self.compiled_excludes.get(share_id)?;
        Some((share, set))
    }
}

/// One entry in a `/tree` response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TreeEntry {
    pub name: String,
    /// Path relative to the share root, forward slashes.
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
}

/// Public, sanitized metadata about a share. Returned by
/// `GET /api/localsend/sync/`. The root path is intentionally not exposed:
/// the receiver never needs to know where the directory lives on the
/// sender's filesystem.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareInfo {
    pub id: String,
    pub name: String,
}

/// Top-level dispatch for sync routes. Called by the v2 server when the
/// request path starts with `/api/localsend/sync/`. `suffix` is the remainder
/// after that prefix, e.g. `{share_id}/manifest`. When `suffix` is empty,
/// the request is for `GET /api/localsend/sync/` itself and returns the
/// list of shares.
pub(crate) async fn handle(
    req: Request<Incoming>,
    state: &SyncHttpState,
    _client_info: &RequestClientInfo,
    suffix: &str,
) -> Result<Response<BoxedBody>, AppError> {
    // No share id: GET /api/localsend/sync/ returns the share list.
    if suffix.is_empty() {
        return match *req.method() {
            Method::GET => list_shares_get(state),
            _ => Err(AppError::Status(StatusCode::NOT_FOUND)),
        };
    }
    let (share_id, action) = match suffix.split_once('/') {
        Some(parts) => parts,
        None => return Err(AppError::Status(StatusCode::NOT_FOUND)),
    };
    let (share, excludes) = match state.lookup(share_id) {
        Some(s) => s,
        None => return Err(AppError::Status(StatusCode::NOT_FOUND)),
    };
    match (req.method(), action) {
        (&Method::GET, "manifest") => manifest_get(share, excludes),
        (&Method::GET, "tree") => tree_get(req, share, excludes).await,
        (&Method::POST, "plan") => plan_post(req, share, excludes).await,
        (&Method::GET, "file") => file_get(req, share).await,
        (&Method::PUT, "file") => file_put(req, share).await,
        _ => Err(AppError::Status(StatusCode::NOT_FOUND)),
    }
}

/// `GET /api/localsend/sync/` -> `[ShareInfo]`. The receiver probes this
/// endpoint on each discovered device to find out which devices expose
/// directory-sync shares.
fn list_shares_get(state: &SyncHttpState) -> Result<Response<BoxedBody>, AppError> {
    let info: Vec<ShareInfo> = state
        .shares
        .iter()
        .map(|s| ShareInfo {
            id: s.id.clone(),
            name: s.name.clone(),
        })
        .collect();
    let bytes = serde_json::to_vec(&info)
        .map_err(|_| AppError::Status(StatusCode::INTERNAL_SERVER_ERROR))?;
    Ok(json_response(StatusCode::OK, bytes))
}

fn manifest_get(
    share: &SyncShareConfig,
    excludes: &GlobSet,
) -> Result<Response<BoxedBody>, AppError> {
    let m = manifest::compute(&share.root, excludes, &share.excludes, &manifest::now_iso())
        .map_err(|e| {
            tracing::warn!("manifest failed for share {}: {e:#}", share.id);
            AppError::Status(StatusCode::INTERNAL_SERVER_ERROR)
        })?;
    let bytes = serde_json::to_vec(&m).map_err(|_| AppError::Status(StatusCode::INTERNAL_SERVER_ERROR))?;
    Ok(json_response(StatusCode::OK, bytes))
}

async fn tree_get(
    req: Request<Incoming>,
    share: &SyncShareConfig,
    excludes: &GlobSet,
) -> Result<Response<BoxedBody>, AppError> {
    let path: String = req
        .uri()
        .query()
        .and_then(|q| q.split('&').find_map(|kv| kv.strip_prefix("path=")))
        .map(urldecode)
        .unwrap_or_default();

    // `/` is the URL-friendly way to ask for the share root. Map it to the
    // empty path so the join is a no-op and `sanitize_relative` stays happy.
    let target_input = if path == "/" { String::new() } else { path };
    let target = sanitize_relative(&target_input)?;
    let abs = share.root.join(&target);
    let meta = std::fs::metadata(&abs)
        .map_err(|_| AppError::Status(StatusCode::NOT_FOUND))?;
    if !meta.is_dir() {
        return Err(AppError::Status(StatusCode::BAD_REQUEST));
    }

    let mut entries: Vec<TreeEntry> = Vec::new();
    let read = std::fs::read_dir(&abs)
        .map_err(|_| AppError::Status(StatusCode::INTERNAL_SERVER_ERROR))?;
    for dent in read.flatten() {
        let name = dent.file_name().to_string_lossy().into_owned();
        let dent_path = dent.path();
        let rel = match dent_path.strip_prefix(&share.root) {
            Ok(p) => p,
            Err(_) => continue,
        };
        let rel_str = path_to_forward(rel);
        if rel_str == ".localsend-sync" || rel_str.starts_with(".localsend-sync/") {
            continue;
        }
        if excludes.is_match(&rel_str) {
            continue;
        }
        let meta = match dent.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        entries.push(TreeEntry {
            name,
            path: rel_str,
            is_dir: meta.is_dir(),
            size: if meta.is_file() { meta.len() } else { 0 },
        });
    }
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    let bytes = serde_json::to_vec(&entries)
        .map_err(|_| AppError::Status(StatusCode::INTERNAL_SERVER_ERROR))?;
    Ok(json_response(StatusCode::OK, bytes))
}

#[derive(Debug, Deserialize)]
struct PlanRequest {
    /// Paths the receiver knew about in the last successful sync.
    #[serde(default)]
    previous_paths: Vec<String>,
    /// Receiver's local manifest.
    local: Manifest,
}

async fn plan_post(
    req: Request<Incoming>,
    share: &SyncShareConfig,
    excludes: &GlobSet,
) -> Result<Response<BoxedBody>, AppError> {
    let body = req.into_body();
    let bytes = match http_body_util::BodyExt::collect(body).await {
        Ok(c) => c.to_bytes(),
        Err(_) => return Err(AppError::Status(StatusCode::BAD_REQUEST)),
    };
    let parsed: PlanRequest = match serde_json::from_slice(&bytes) {
        Ok(p) => p,
        Err(_) => return Err(AppError::Status(StatusCode::BAD_REQUEST)),
    };
    let remote = manifest::compute(&share.root, excludes, &share.excludes, &manifest::now_iso())
        .map_err(|_| AppError::Status(StatusCode::INTERNAL_SERVER_ERROR))?;
    let plan = diff::compute(&remote, &parsed.local, &parsed.previous_paths, &manifest::now_iso());
    let bytes = serde_json::to_vec(&plan)
        .map_err(|_| AppError::Status(StatusCode::INTERNAL_SERVER_ERROR))?;
    Ok(json_response(StatusCode::OK, bytes))
}

async fn file_get(
    req: Request<Incoming>,
    share: &SyncShareConfig,
) -> Result<Response<BoxedBody>, AppError> {
    let path: String = req
        .uri()
        .query()
        .and_then(|q| q.split('&').find_map(|kv| kv.strip_prefix("path=")))
        .map(urldecode)
        .unwrap_or_default();
    let target = sanitize_relative(&path)?;
    let abs = share.root.join(&target);
    let meta = std::fs::metadata(&abs)
        .map_err(|_| AppError::Status(StatusCode::NOT_FOUND))?;
    if !meta.is_file() {
        return Err(AppError::Status(StatusCode::BAD_REQUEST));
    }
    let file = tokio::fs::File::open(&abs)
        .await
        .map_err(|_| AppError::Status(StatusCode::INTERNAL_SERVER_ERROR))?;
    let stream = ReaderStream::new(file).map(|res| {
        res.map(|bytes| Frame::data(bytes))
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)
    });
    // Map every error to a sentinel io::Error so the body type matches BoxedBody.
    let stream = stream.map(|res| match res {
        Ok(frame) => Ok(frame),
        Err(_) => Err(std::io::Error::other("sync file stream")),
    });
    let body = StreamBody::new(stream);
    let boxed: BoxedBody = BodyExt::boxed(body);
    let mut response = Response::new(boxed);
    let headers = response.headers_mut();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/octet-stream"));
    headers.insert(CONTENT_LENGTH, HeaderValue::from(meta.len()));
    Ok(response)
}

async fn file_put(
    req: Request<Incoming>,
    share: &SyncShareConfig,
) -> Result<Response<BoxedBody>, AppError> {
    // v1 stub: write the body to the share's root under a temporary name.
    // The Dart side is expected to confirm with a real upload flow before v2.
    let body = req.into_body();
    let bytes = match http_body_util::BodyExt::collect(body).await {
        Ok(c) => c.to_bytes(),
        Err(_) => return Err(AppError::Status(StatusCode::BAD_REQUEST)),
    };
    let staged = share.root.join(format!(".localsend-sync-upload-{}", uuid::Uuid::new_v4()));
    if let Some(parent) = staged.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    if let Err(e) = std::fs::write(&staged, &bytes) {
        tracing::warn!("sync file_put write {} failed: {e}", staged.display());
        return Err(AppError::Status(StatusCode::INTERNAL_SERVER_ERROR));
    }
    let resp = serde_json::json!({
        "staged_path": staged.to_string_lossy(),
        "bytes": bytes.len(),
    });
    let bytes = serde_json::to_vec(&resp)
        .map_err(|_| AppError::Status(StatusCode::INTERNAL_SERVER_ERROR))?;
    Ok(json_response(StatusCode::CREATED, bytes))
}

fn json_response(status: StatusCode, body: Vec<u8>) -> Response<BoxedBody> {
    let body = response::full_body(Bytes::from(body));
    let mut response = Response::new(body);
    *response.status_mut() = status;
    let headers = response.headers_mut();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    response
}

/// Reject anything that tries to escape the share root with `..` or absolute
/// paths, and normalize separators.
fn sanitize_relative(input: &str) -> Result<PathBuf, AppError> {
    let p = Path::new(input);
    for c in p.components() {
        match c {
            Component::ParentDir => {
                return Err(AppError::Status(StatusCode::BAD_REQUEST));
            }
            Component::RootDir | Component::Prefix(_) => {
                return Err(AppError::Status(StatusCode::BAD_REQUEST));
            }
            _ => {}
        }
    }
    Ok(p.to_path_buf())
}

fn path_to_forward(p: &Path) -> String {
    p.components()
        .map(|c| c.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("/")
}

/// Minimal URL-decode (handles `%XX` and `+`). `urlencoding` is not currently
/// a dependency of this module, so we keep it self-contained.
fn urldecode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            b'%' if i + 2 < bytes.len() => {
                let hi = from_hex(bytes[i + 1]);
                let lo = from_hex(bytes[i + 2]);
                match (hi, lo) {
                    (Some(h), Some(l)) => {
                        out.push((h << 4) | l);
                        i += 3;
                    }
                    _ => {
                        out.push(bytes[i]);
                        i += 1;
                    }
                }
            }
            b => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn from_hex(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_rejects_parent_dir() {
        assert!(sanitize_relative("a/../b").is_err());
        assert!(sanitize_relative("../etc/passwd").is_err());
    }

    #[test]
    fn sanitize_rejects_absolute() {
        assert!(sanitize_relative("/etc/passwd").is_err());
    }

    #[test]
    fn sanitize_accepts_normal() {
        assert_eq!(
            sanitize_relative("sub/dir/file.txt").unwrap(),
            PathBuf::from("sub/dir/file.txt")
        );
    }

    #[test]
    fn urldecode_basic() {
        assert_eq!(urldecode("hello+world"), "hello world");
        assert_eq!(urldecode("a%2Fb"), "a/b");
        assert_eq!(urldecode("%E4%B8%AD"), "中");
    }

    #[test]
    fn sync_http_state_lookup() {
        let s = SyncHttpState::new(vec![SyncShareConfig {
            id: "abc".into(),
            name: "share1".into(),
            root: PathBuf::from("/tmp"),
            excludes: vec!["*.tmp".into()],
        }]);
        assert!(s.lookup("abc").is_some());
        assert!(s.lookup("missing").is_none());
    }

    #[test]
    fn sync_http_state_drops_invalid_patterns() {
        let s = SyncHttpState::new(vec![SyncShareConfig {
            id: "abc".into(),
            name: "share1".into(),
            root: PathBuf::from("/tmp"),
            excludes: vec!["[unterminated".into()],
        }]);
        // The share itself still exists, but its compiled_excludes was dropped
        // so lookup returns None.
        assert!(s.lookup("abc").is_none());
    }
}
