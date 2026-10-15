import 'package:flutter/foundation.dart';
import 'package:localsend_app/provider/sync/browse_state.dart';
import 'package:localsend_app/provider/sync/plan_response.dart';
import 'package:localsend_app/provider/sync/sync_http_client.dart';

/// One in-progress sync session, scoped to a (device, share, target) triple.
///
/// The state machine has six distinct phases; transitions are driven by
/// [StartSyncAction] and the smaller actions listed in
/// `sync_session_provider.dart`. The session is intentionally *single*:
/// starting a new sync while one is active throws the previous one away
/// (matching how the browse state works).
@immutable
class SyncSessionState {
  /// Snapshot of the (device, share, target) the user picked. The
  /// session never re-reads [syncBrowseProvider] — it carries the
  /// resolved values with it so the user can pop the browse page
  /// without losing the in-flight download.
  final BrowseState browse;

  /// The sender's manifest, captured at the start of the session.
  final RemoteSyncManifest? remoteManifest;

  /// The diff result the sender returned.
  final RemoteSyncPlan? plan;

  /// Per-file status keyed by `path` (the same forward-slash path the
  /// sender uses). Keys exist for every path in `plan.downloads` once
  /// the plan is received, and are created with [FileSyncStatus.pending].
  final Map<String, FileSyncStatus> fileStatus;

  /// How the user resolved each conflict. Absent means "still pending".
  final Map<String, ConflictResolution> conflictDecisions;

  /// The current phase. Drives the [SyncSessionPage] UI.
  final SyncPhase phase;

  /// Human-readable error message. Only set when [phase] is [SyncPhase.failed].
  final String? error;

  const SyncSessionState({
    required this.browse,
    this.remoteManifest,
    this.plan,
    this.fileStatus = const {},
    this.conflictDecisions = const {},
    this.phase = SyncPhase.idle,
    this.error,
  });

  /// True while the session is doing something the user might want to
  /// cancel (downloading, computing the plan, fetching the manifest).
  bool get isActive =>
      phase == SyncPhase.fetchingManifest ||
      phase == SyncPhase.submittingPlan ||
      phase == SyncPhase.downloading ||
      phase == SyncPhase.resolvingConflicts;

  bool get isComplete => phase == SyncPhase.done;
  bool get isFailed => phase == SyncPhase.failed;
  bool get isCancelled => phase == SyncPhase.cancelled;

  /// Convenience counters used by the summary banner.
  int get downloadedCount =>
      fileStatus.values.where((s) => s == FileSyncStatus.done).length;
  int get failedCount =>
      fileStatus.values.where((s) => s == FileSyncStatus.failed).length;
  int get skippedCount =>
      fileStatus.values.where((s) => s == FileSyncStatus.skipped).length;
  int get pendingCount =>
      fileStatus.values.where((s) => s == FileSyncStatus.pending || s == FileSyncStatus.downloading).length;
}

/// The 7 phases of a sync session, mirroring `support/sync_design.md` §7.
enum SyncPhase {
  /// No session is running.
  idle,

  /// Fetching the sender's manifest over HTTP.
  fetchingManifest,

  /// Posting the local manifest to the sender and waiting for the plan.
  submittingPlan,

  /// Iterating over `plan.downloads` and writing each file to disk.
  downloading,

  /// Waiting for the user to pick a side on every conflict.
  resolvingConflicts,

  /// All transfers done; the user can dismiss the page.
  done,

  /// Something went wrong (network drop, write error, etc.).
  failed,

  /// The user pressed Cancel; partial state is kept.
  cancelled,
}

/// Per-file progress, mapped onto an icon in the list.
enum FileSyncStatus {
  pending,
  downloading,
  done,
  failed,
  skipped,
}

/// How the user wants to settle one conflict.
enum ConflictResolution {
  /// Keep the local version, drop the remote one.
  keepLocal,

  /// Discard the local version, write the remote one in its place.
  keepRemote,

  /// Write the remote version under `<path>.remote` next to the local
  /// one so the user can compare them by hand.
  keepBoth,

  /// Skip the path entirely. No write happens.
  skip,
}
