import 'dart:async';
import 'dart:io';

import 'package:localsend_app/provider/sync/browse_state.dart';
import 'package:localsend_app/provider/sync/plan_response.dart';
import 'package:localsend_app/provider/sync/sync_http_client.dart';
import 'package:localsend_app/provider/sync/sync_session_state.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The single, global sync session. `null` means "no session running".
///
/// One [SyncSessionState] per app lifetime: starting a new sync replaces
/// the current one (the previous one is silently dropped). This matches
/// how [syncBrowseProvider] works and is enough for v1 — there is no UI
/// that needs to track more than one session at a time.
final syncSessionProvider = ReduxProvider<SyncSessionService, SyncSessionState?>((ref) {
  return SyncSessionService();
});

class SyncSessionService extends ReduxNotifier<SyncSessionState?> {
  @override
  SyncSessionState? init() => null;
}

/// Replaces the current session wholesale. Used by [StartSyncAction] to
/// advance the state machine between phases.
class _ReplaceSessionAction extends ReduxAction<SyncSessionService, SyncSessionState?> {
  final SyncSessionState? next;
  _ReplaceSessionAction(this.next);

  @override
  SyncSessionState? reduce() => next;
}

/// Replaces just the per-file status map. Used between downloads.
class _SetFileStatusesAction extends ReduxAction<SyncSessionService, SyncSessionState?> {
  final Map<String, FileSyncStatus> statuses;
  _SetFileStatusesAction(this.statuses);

  @override
  SyncSessionState? reduce() {
    final s = state;
    if (s == null) {
      return null;
    }
    return SyncSessionState(
      browse: s.browse,
      remoteManifest: s.remoteManifest,
      plan: s.plan,
      fileStatus: statuses,
      conflictDecisions: s.conflictDecisions,
      phase: s.phase,
      error: s.error,
    );
  }
}

/// Records how the user resolved [path]. The UI dispatches one of these
/// per conflict; the page can then call [StartSyncAction.settle] to
/// apply the decisions.
class ResolveConflictAction extends ReduxAction<SyncSessionService, SyncSessionState?> {
  final String path;
  final ConflictResolution decision;

  ResolveConflictAction({required this.path, required this.decision});

  @override
  SyncSessionState? reduce() {
    final s = state;
    if (s == null || s.plan == null) {
      return state;
    }
    final decisions = {...s.conflictDecisions, path: decision};
    return SyncSessionState(
      browse: s.browse,
      remoteManifest: s.remoteManifest,
      plan: s.plan,
      fileStatus: s.fileStatus,
      conflictDecisions: decisions,
      phase: s.phase,
      error: s.error,
    );
  }
}

/// Runs the full state machine: fetch manifest, post plan, download
  /// each file, ask the user about each conflict, settle. The action is
  /// async because each network round-trip awaits; the UI is updated
  /// between steps by dispatching [_ReplaceSessionAction] in a tight
  /// loop.
  ///
  /// When conflicts remain after the download phase, this action stops
  /// with [SyncPhase.resolvingConflicts] and returns the current state;
  /// the UI then dispatches [SettleConflictsAction] once every conflict
  /// has a [ResolveConflictAction] in [SyncSessionState.conflictDecisions].
class StartSyncAction extends AsyncReduxAction<SyncSessionService, SyncSessionState?> {
  final BrowseState browse;

  StartSyncAction({required this.browse});

  @override
  Future<SyncSessionState?> reduce() async {
    final channel = firstHttpChannel(browse.device);
    if (channel == null) {
      return _fail('Sender has no HTTP channel.');
    }
    if (browse.targetRoot == null) {
      return _fail('No target directory chosen.');
    }
    final targetRoot = browse.targetRoot!;

    final client = SyncHttpClient(host: channel.host, port: channel.port, useTls: channel.https);

    // Phase 1: fetch the manifest.
    dispatch(_ReplaceSessionAction(SyncSessionState(
      browse: browse,
      phase: SyncPhase.fetchingManifest,
    )));
    final RemoteSyncManifest manifest;
    try {
      manifest = await client.getManifest(browse.share.id);
    } on SyncHttpException catch (e) {
      return _fail('Manifest fetch failed: $e');
    } catch (e) {
      return _fail('Manifest fetch failed: $e');
    }

    // Phase 2: post the plan. v1 sends an empty local manifest and no
    // previous paths (no sync state yet, see PR 7). The server still
    // returns a useful plan: every selected file lands in `downloads`
    // unless the diff flags it as a conflict.
    dispatch(_ReplaceSessionAction(SyncSessionState(
      browse: browse,
      remoteManifest: manifest,
      phase: SyncPhase.submittingPlan,
    )));
    final RemoteSyncPlan plan;
    try {
      plan = await client.postPlan(browse.share.id, local: const [], previousPaths: const []);
    } on SyncHttpException catch (e) {
      return _fail('Plan request failed: $e');
    } catch (e) {
      return _fail('Plan request failed: $e');
    }

    // Initialize per-file status: every download path is pending.
    final statuses = <String, FileSyncStatus>{
      for (final d in plan.downloads) d.path: FileSyncStatus.pending,
    };
    dispatch(_ReplaceSessionAction(SyncSessionState(
      browse: browse,
      remoteManifest: manifest,
      plan: plan,
      fileStatus: statuses,
      phase: SyncPhase.downloading,
    )));

    // Phase 3: download each file in order. v1 is serial; PR 8+ can
    // parallelize. The loop checks [CancelSyncAction] between files
    // via the provider state.
    for (final transfer in plan.downloads) {
      final current = state;
      if (current?.phase == SyncPhase.cancelled) {
        return state;
      }
      statuses[transfer.path] = FileSyncStatus.downloading;
      dispatch(_SetFileStatusesAction(Map.unmodifiable(statuses)));
      try {
        await _downloadOne(client, browse.share.id, transfer.path, targetRoot);
        statuses[transfer.path] = FileSyncStatus.done;
      } catch (e) {
        statuses[transfer.path] = FileSyncStatus.failed;
        dispatch(_SetFileStatusesAction(Map.unmodifiable(statuses)));
        return _fail('Download failed for ${transfer.path}: $e');
      }
      dispatch(_SetFileStatusesAction(Map.unmodifiable(statuses)));
    }

    // Phase 4: hand off to the UI for conflict resolution. Every
    // conflict is pending; the page dispatches [ResolveConflictAction]
    // for each one and then [SettleConflictsAction] to apply them.
    if (plan.conflicts.isNotEmpty) {
      dispatch(_ReplaceSessionAction(SyncSessionState(
        browse: browse,
        remoteManifest: manifest,
        plan: plan,
        fileStatus: statuses,
        phase: SyncPhase.resolvingConflicts,
      )));
      return state;
    }

    // No conflicts: settle skipped entries and finish.
    for (final s in plan.skips) {
      statuses[s.path] = FileSyncStatus.skipped;
    }
    dispatch(_ReplaceSessionAction(SyncSessionState(
      browse: browse,
      remoteManifest: manifest,
      plan: plan,
      fileStatus: statuses,
      phase: SyncPhase.done,
    )));
    return state;
  }

  SyncSessionState? _fail(String message) {
    final s = state;
    final next = SyncSessionState(
      browse: browse,
      remoteManifest: s?.remoteManifest,
      plan: s?.plan,
      fileStatus: s?.fileStatus ?? const {},
      conflictDecisions: s?.conflictDecisions ?? const {},
      phase: SyncPhase.failed,
      error: message,
    );
    dispatch(_ReplaceSessionAction(next));
    return next;
  }
}

/// Applies every queued [ResolveConflictAction] in
/// [SyncSessionState.conflictDecisions] and moves the session to
/// [SyncPhase.done]. Dispatched by the UI after the user has answered
/// every [SyncConflictDialog]. If any decision is missing the session
/// is left in [SyncPhase.resolvingConflicts] so the page can ask again.
class SettleConflictsAction extends AsyncReduxAction<SyncSessionService, SyncSessionState?> {
  @override
  Future<SyncSessionState?> reduce() async {
    final s = state;
    if (s == null || s.plan == null || s.phase != SyncPhase.resolvingConflicts) {
      return state;
    }
    final targetRoot = s.browse.targetRoot!;
    final channel = firstHttpChannel(s.browse.device)!;
    final client = SyncHttpClient(host: channel.host, port: channel.port, useTls: channel.https);
    final statuses = Map<String, FileSyncStatus>.from(s.fileStatus);
    for (final c in s.plan!.conflicts) {
      final decision = s.conflictDecisions[c.path];
      if (decision == null) {
        // The UI should not dispatch this while decisions are missing.
        return state;
      }
      try {
        await _applyConflictResolution(client, s.browse.share.id, c.path, decision, targetRoot);
        statuses[c.path] = decision == ConflictResolution.skip ? FileSyncStatus.skipped : FileSyncStatus.done;
      } catch (e) {
        statuses[c.path] = FileSyncStatus.failed;
      }
    }
    for (final skip in s.plan!.skips) {
      statuses[skip.path] = FileSyncStatus.skipped;
    }
    dispatch(_ReplaceSessionAction(SyncSessionState(
      browse: s.browse,
      remoteManifest: s.remoteManifest,
      plan: s.plan,
      fileStatus: Map.unmodifiable(statuses),
      phase: SyncPhase.done,
    )));
    return state;
  }
}

/// Flips the session to [SyncPhase.cancelled]. The download loop checks
/// the current phase between files and bails out.
class CancelSyncAction extends ReduxAction<SyncSessionService, SyncSessionState?> {
  @override
  SyncSessionState? reduce() {
    final s = state;
    if (s == null) {
      return state;
    }
    return SyncSessionState(
      browse: s.browse,
      remoteManifest: s.remoteManifest,
      plan: s.plan,
      fileStatus: s.fileStatus,
      conflictDecisions: s.conflictDecisions,
      phase: SyncPhase.cancelled,
      error: s.error,
    );
  }
}

/// Clears the session back to `null`. The user dismisses the page.
class ResetSyncAction extends ReduxAction<SyncSessionService, SyncSessionState?> {
  @override
  SyncSessionState? reduce() => null;
}

/// Fetches one file from the sender and writes it to
/// `<targetRoot>/<path>`. v1 buffers the whole body in memory (files
/// are small in practice; the sender already buffers the file too).
Future<void> _downloadOne(SyncHttpClient client, String shareId, String path, String targetRoot) async {
  final bytes = await client.getFile(shareId, path);
  final dest = File('$targetRoot${Platform.pathSeparator}$path');
  await dest.parent.create(recursive: true);
  await dest.writeAsBytes(bytes, flush: true);
}

/// Applies a single conflict resolution by either skipping the file,
/// writing the remote version to its place, or writing the remote
/// version under `<path>.remote` next to the local one.
Future<void> _applyConflictResolution(
  SyncHttpClient client,
  String shareId,
  String path,
  ConflictResolution decision,
  String targetRoot,
) async {
  final base = File('$targetRoot${Platform.pathSeparator}$path');
  switch (decision) {
    case ConflictResolution.keepLocal:
      return;
    case ConflictResolution.keepRemote:
      final bytes = await client.getFile(shareId, path);
      await base.parent.create(recursive: true);
      await base.writeAsBytes(bytes, flush: true);
    case ConflictResolution.keepBoth:
      final bytes = await client.getFile(shareId, path);
      final alt = File('${base.path}.remote');
      await alt.parent.create(recursive: true);
      await alt.writeAsBytes(bytes, flush: true);
    case ConflictResolution.skip:
      return;
  }
}
