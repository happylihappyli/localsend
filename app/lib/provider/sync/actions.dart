import 'package:localsend_app/provider/sync/sync_session.dart';
import 'package:localsend_app/provider/sync/sync_sessions_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Higher-level actions that mutate the [SyncSessionsService]. They exist
/// in a separate file from the provider so the reducer itself stays small
/// and the transitions read like the state machine in
/// `support/sync_design.md` §7.
class PlanSyncSessionAction extends AsyncReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final String id;
  final int totalTransfers;

  PlanSyncSessionAction({required this.id, required this.totalTransfers});

  @override
  Future<Map<String, SyncSession>> reduce() async {
    return Map<String, SyncSession>.unmodifiable({
      ...state,
      id: state[id]!.copyState(
        state: totalTransfers == 0 ? SyncSessionState.done : SyncSessionState.planning,
        totalTransfers: totalTransfers,
        completedTransfers: 0,
      ),
    });
  }
}

class OpenConflictsAction extends AsyncReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final String id;
  final List<ConflictEntry> conflicts;

  OpenConflictsAction({required this.id, required this.conflicts});

  @override
  Future<Map<String, SyncSession>> reduce() async {
    if (conflicts.isEmpty) {
      // No conflicts: the session is ready to download straight away.
      return Map<String, SyncSession>.unmodifiable({
        ...state,
        id: state[id]!.copyState(state: SyncSessionState.downloading),
      });
    }
    return Map<String, SyncSession>.unmodifiable({
      ...state,
      id: state[id]!.copyState(
        state: SyncSessionState.resolvingConflicts,
        openConflicts: conflicts,
      ),
    });
  }
}

class ResolveConflictAction extends AsyncReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final String id;
  final String path;
  final ConflictResolution resolution;

  ResolveConflictAction({required this.id, required this.path, required this.resolution});

  @override
  Future<Map<String, SyncSession>> reduce() async {
    final current = state[id];
    if (current == null) {
      return state;
    }
    final remaining = current.openConflicts.where((c) => c.path != path).toList(growable: false);
    final nextState = remaining.isEmpty ? SyncSessionState.downloading : SyncSessionState.resolvingConflicts;
    return Map<String, SyncSession>.unmodifiable({
      ...state,
      id: current.copyState(
        state: nextState,
        openConflicts: List<ConflictEntry>.unmodifiable(remaining),
      ),
    });
  }
}

class AdvanceTransferAction extends AsyncReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final String id;

  AdvanceTransferAction(this.id);

  @override
  Future<Map<String, SyncSession>> reduce() async {
    final current = state[id];
    if (current == null) {
      return state;
    }
    final completed = current.completedTransfers + 1;
    final finished = completed >= current.totalTransfers;
    return Map<String, SyncSession>.unmodifiable({
      ...state,
      id: current.copyState(
        state: finished ? SyncSessionState.done : SyncSessionState.downloading,
        completedTransfers: completed,
      ),
    });
  }
}

class CancelSyncSessionAction extends AsyncReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final String id;

  CancelSyncSessionAction(this.id);

  @override
  Future<Map<String, SyncSession>> reduce() async {
    final current = state[id];
    if (current == null) {
      return state;
    }
    return Map<String, SyncSession>.unmodifiable({
      ...state,
      id: current.copyState(
        state: SyncSessionState.cancelled,
        clearError: true,
      ),
    });
  }
}

class FailSyncSessionAction extends AsyncReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final String id;
  final String error;

  FailSyncSessionAction({required this.id, required this.error});

  @override
  Future<Map<String, SyncSession>> reduce() async {
    final current = state[id];
    if (current == null) {
      return state;
    }
    return Map<String, SyncSession>.unmodifiable({
      ...state,
      id: current.copyState(
        state: SyncSessionState.failed,
        error: error,
      ),
    });
  }
}
