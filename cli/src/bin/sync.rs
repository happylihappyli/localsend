//! Headless CLI wrapper around the LocalSend directory-sync endpoints.
//!
//! Two subcommands are exposed:
//! - `server`: run a v2 server with a single sync share, plain HTTP (no TLS).
//! - `client`: pull a share from a peer into a local directory, with simple
//!   keep-local conflict handling.
//!
//! Lives in `cli/src/bin/sync.rs` so the interactive TUI binary
//! `localsend-cli` keeps its current behavior. The CLI does not need TLS
//! because the share content here is whatever the operator decides to expose;
//! production users are expected to put a reverse proxy in front or use the
//! main app's TLS server.

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use localsend::http::server::v2::ServerEventV2;
use localsend::http::server::web::WebConfig;
use localsend::http::server::{start_with_port, ServerConfigV2};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::DeviceType;
use localsend::sync::http::SyncShareConfig;
use localsend::sync::manifest::{self, compile_excludes};
use localsend::sync::Manifest;
use serde::Deserialize;
use std::path::PathBuf;
use tokio::sync::{mpsc, oneshot};

#[derive(Parser)]
#[command(
    name = "localsend-cli-sync",
    version,
    about = "Headless wrapper around the LocalSend directory-sync endpoints"
)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Run a v2 server exposing a single sync share.
    Server(ServerOpts),
    /// Pull a share from a peer and write files into a local directory.
    Client(ClientOpts),
}

#[derive(Parser)]
struct ServerOpts {
    /// Local directory to share.
    #[arg(long)]
    root: PathBuf,

    /// Path to a gitignore-style exclude file (one pattern per line).
    #[arg(long, default_value = ".syncignore")]
    ignore: PathBuf,

    /// Alias shown to other devices.
    #[arg(long, env = "LOCALSEND_ALIAS")]
    alias: Option<String>,

    /// TCP port to listen on.
    #[arg(long, default_value_t = 53318)]
    port: u16,

    /// Stable share id (clients need it to look up the share). Defaults to a UUID.
    #[arg(long)]
    share_id: Option<String>,
}

#[derive(Parser)]
struct ClientOpts {
    /// Peer base URL, e.g. http://192.168.1.5:53318
    #[arg(long)]
    peer: String,

    /// Local directory to receive files into.
    #[arg(long)]
    target: PathBuf,

    /// Share id. Defaults to the first share returned by the peer.
    #[arg(long)]
    share_id: Option<String>,

    /// What to do with conflicts (sha256 differs on both sides).
    /// `keep-local` (default) leaves the local copy untouched,
    /// `keep-remote` overwrites with the remote version,
    /// `abort` exits non-zero.
    #[arg(long, default_value = "keep-local", value_parser = ["keep-local", "keep-remote", "abort"])]
    conflict: String,

    /// Print what would happen, but make no changes.
    #[arg(long)]
    dry_run: bool,

    /// Log every downloaded file.
    #[arg(short, long)]
    verbose: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Install a rustls crypto provider before any `reqwest::Client` is built.
    // The core crate re-exports reqwest with `rustls-no-provider`, so the
    // provider must be installed by the binary.
    let _ = rustls::crypto::ring::default_provider().install_default();

    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Server(o) => run_server(o).await,
        Cmd::Client(o) => run_client(o).await,
    }
}

fn read_excludes(path: &PathBuf) -> Result<Vec<String>> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("read exclude file {}", path.display()))?;
    Ok(text.lines().map(String::from).collect())
}

async fn run_server(o: ServerOpts) -> Result<()> {
    let excludes = read_excludes(&o.ignore)?;
    let root = o
        .root
        .canonicalize()
        .with_context(|| format!("canonicalize {}", o.root.display()))?;
    if !root.is_dir() {
        anyhow::bail!("--root is not a directory: {}", root.display());
    }

    let alias = o.alias.clone().unwrap_or_else(|| {
        root.file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("share")
            .to_string()
    });
    let share_id = o
        .share_id
        .clone()
        .unwrap_or_else(|| format!("cli-sync-{}", uuid::Uuid::new_v4()));
    let share_name = alias.clone();

    // Validate the patterns compile before we open the port.
    let _ = compile_excludes(excludes.iter().map(String::as_str))
        .context("invalid exclude pattern")?;

    let client_info = ClientInfo {
        alias: alias.clone(),
        version: "2.0".to_string(),
        device_model: Some("localsend-cli-sync".to_string()),
        device_type: Some(DeviceType::Headless),
        token: format!("cli-sync-{}", uuid::Uuid::new_v4()),
    };

    let share = SyncShareConfig {
        id: share_id.clone(),
        name: share_name.clone(),
        root: root.clone(),
        excludes: excludes.clone(),
    };

    println!(
        "Sharing {root} as '{name}' (id={id}) with {n} excludes",
        root = root.display(),
        name = share_name,
        id = share_id,
        n = excludes.len()
    );
    println!("Listening on 0.0.0.0:{port} (plain HTTP)", port = o.port);

    let (event_tx, _event_rx) = mpsc::channel::<ServerEventV2>(16);
    let (_stop_tx, stop_rx) = oneshot::channel();

    let handle = start_with_port(
        o.port,
        None, // plain HTTP; the TUI binary handles TLS
        client_info,
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: false,
            event_tx,
            sync_shares: vec![share],
        }),
        WebConfig::default(),
        stop_rx,
    )
    .await
    .context("start server")?;

    println!("Press Ctrl+C to stop.");
    tokio::signal::ctrl_c().await.ok();
    println!("Stopping...");
    drop(handle);
    Ok(())
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct ShareInfo {
    id: String,
    name: String,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct Transfer {
    path: String,
    size: u64,
    #[serde(default)]
    sha256: String,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct Conflict {
    path: String,
    #[serde(default)]
    local_mtime_unix: i64,
    #[serde(default)]
    remote_mtime_unix: i64,
    #[serde(default)]
    local_sha256: String,
    #[serde(default)]
    remote_sha256: String,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct PlanResponse {
    #[serde(default)]
    downloads: Vec<Transfer>,
    #[serde(default)]
    conflicts: Vec<Conflict>,
    #[serde(default)]
    uploads: Vec<Transfer>,
}

async fn run_client(o: ClientOpts) -> Result<()> {
    let base = o.peer.trim_end_matches('/').to_string();

    // 1. Discover available shares.
    println!("Probing {base}/api/localsend/sync/ ...");
    let shares: Vec<ShareInfo> = localsend::reqwest::get(format!("{base}/api/localsend/sync/"))
        .await
        .context("list shares")?
        .error_for_status()?
        .json()
        .await
        .context("decode shares")?;
    if shares.is_empty() {
        anyhow::bail!("peer exposes no sync shares");
    }
    let share_id = match o.share_id.as_deref() {
        Some(id) => id.to_string(),
        None => shares[0].id.clone(),
    };
    println!("Using share id: {share_id} (peer: {})", shares[0].name);

    // 2. Compute local manifest.
    tokio::fs::create_dir_all(&o.target)
        .await
        .with_context(|| format!("create target {}", o.target.display()))?;
    let local_set = compile_excludes::<_, &str>([]).context("compile empty excludes")?;
    let local_manifest: Manifest = manifest::compute(
        &o.target,
        &local_set,
        &[],
        &manifest::now_iso(),
    )
    .context("compute local manifest")?;
    println!(
        "Local: {n} entries under {t}",
        n = local_manifest.entries.len(),
        t = o.target.display()
    );

    // 3. POST plan.
    let body = serde_json::json!({
        "previous_paths": [],
        "local": local_manifest,
    });
    let plan: PlanResponse = localsend::reqwest::Client::new()
        .post(format!("{base}/api/localsend/sync/{share_id}/plan"))
        .json(&body)
        .send()
        .await
        .context("post plan")?
        .error_for_status()?
        .json()
        .await
        .context("decode plan")?;
    println!(
        "Plan: {} to download, {} conflicts, {} uploads",
        plan.downloads.len(),
        plan.conflicts.len(),
        plan.uploads.len()
    );

    // 4. Conflicts: per the default CLI policy (keep-local), the local copy
    // is preserved. We log them so the operator can resolve manually.
    //
    // `keep-remote` re-issues the GET for each conflicted path, which
    // overwrites the local copy. The plan itself does not list conflicts
    // in `downloads` because the server has no way to know the receiver
    // would want them overwritten; the client decides.
    let mut override_paths: Vec<&str> = Vec::new();
    if !plan.conflicts.is_empty() {
        match o.conflict.as_str() {
            "keep-local" => {
                println!(
                    "Conflicts ({}): keeping local copy. Resolve manually:",
                    plan.conflicts.len()
                );
                for c in &plan.conflicts {
                    println!(
                        "  {path}  local_sha={ls} remote_sha={rs}",
                        path = c.path,
                        ls = short(&c.local_sha256),
                        rs = short(&c.remote_sha256)
                    );
                }
            }
            "abort" => {
                anyhow::bail!(
                    "{} conflicts found and --conflict=abort set; exiting",
                    plan.conflicts.len()
                );
            }
            "keep-remote" => {
                println!(
                    "Conflicts ({}): will overwrite with remote version (--conflict=keep-remote).",
                    plan.conflicts.len()
                );
                override_paths = plan.conflicts.iter().map(|c| c.path.as_str()).collect();
            }
            _ => unreachable!("validated by clap"),
        }
    }

    // 5. Download (regular + conflict overrides).
    let total = plan.downloads.len() + override_paths.len();
    if total == 0 {
        println!("Nothing to download.");
        return Ok(());
    }
    if o.dry_run {
        println!("DRY RUN: would download {} files:", total);
        for d in &plan.downloads {
            println!("  {} ({} bytes)", d.path, d.size);
        }
        for p in &override_paths {
            println!("  {} (overwrite)", p);
        }
        return Ok(());
    }

    let client = localsend::reqwest::Client::new();
    let mut downloaded = 0u64;
    for d in &plan.downloads {
        let res = client
            .get(format!(
                "{base}/api/localsend/sync/{share_id}/file?path={path}",
                path = d.path
            ))
            .send()
            .await
            .with_context(|| format!("GET {}", d.path))?
            .error_for_status()
            .with_context(|| format!("server rejected {}", d.path))?;
        let bytes = res.bytes().await.context("read body")?;
        let local = o.target.join(&d.path);
        if let Some(parent) = local.parent() {
            tokio::fs::create_dir_all(parent).await.context("mkdir")?;
        }
        tokio::fs::write(&local, &bytes)
            .await
            .with_context(|| format!("write {}", local.display()))?;
        downloaded += 1;
        if o.verbose {
            println!("  downloaded {} ({} bytes)", d.path, bytes.len());
        }
    }
    for path in &override_paths {
        let res = client
            .get(format!(
                "{base}/api/localsend/sync/{share_id}/file?path={path}"
            ))
            .send()
            .await
            .with_context(|| format!("GET override {path}"))?
            .error_for_status()
            .with_context(|| format!("server rejected override {path}"))?;
        let bytes = res.bytes().await.context("read override body")?;
        let local = o.target.join(path);
        if let Some(parent) = local.parent() {
            tokio::fs::create_dir_all(parent).await.context("mkdir")?;
        }
        tokio::fs::write(&local, &bytes)
            .await
            .with_context(|| format!("write override {}", local.display()))?;
        downloaded += 1;
        if o.verbose {
            println!("  overwritten {} ({} bytes)", path, bytes.len());
        }
    }

    println!(
        "Done: {downloaded} downloaded, {} conflicts, 0 skipped",
        plan.conflicts.len()
    );
    Ok(())
}

fn short(sha: &str) -> &str {
    if sha.len() <= 12 {
        sha
    } else {
        &sha[..12]
    }
}
