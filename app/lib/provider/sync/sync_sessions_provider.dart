import 'package:localsend_app/provider/sync/sync_session.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// In-memory state for the directory-sync sessions the user has started in
/// this app instance. Sessions are keyed by the `id` of the local copy of
/// the session (created by `StartSyncSessionAction`), so the same peer can
/// have at most one active session per share at a time.
///
/// The persistent counterpart (`.localsend-sync/{id}.json`) is written by
/// the receiver side; it is not held here. This provider is re-created
/// from scratch on every app start.
final syncSessionsProvider =
    ReduxProvider<SyncSessionsService, Map<String, SyncSession>>((ref) {
  return SyncSessionsService();
});

class SyncSessionsService extends ReduxNotifier<Map<String, SyncSession>> {
  @override
  Map<String, SyncSession> init() => const {};
}

class StartSyncSessionAction extends ReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final SyncSession session;

  StartSyncSessionAction(this.session);

  @override
  Map<String, SyncSession> reduce() {
    return Map<String, SyncSession>.unmodifiable({
      ...state,
      session.id: session,
    });
  }
}

class UpdateSyncSessionAction
    extends ReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final String id;
  final SyncSession Function(SyncSession current) update;

  UpdateSyncSessionAction({required this.id, required this.update});

  @override
  Map<String, SyncSession> reduce() {
    final current = state[id];
    if (current == null) {
      return state;
    }
    final next = update(current);
    if (identical(next, current)) {
      return state;
    }
    return Map<String, SyncSession>.unmodifiable({
      ...state,
      id: next,
    });
  }
}

class EndSyncSessionAction extends ReduxAction<SyncSessionsService, Map<String, SyncSession>> {
  final String id;

  EndSyncSessionAction(this.id);

  @override
  Map<String, SyncSession> reduce() {
    if (!state.containsKey(id)) {
      return state;
    }
    final next = Map<String, SyncSession>.from(state)..remove(id);
    return Map<String, SyncSession>.unmodifiable(next);
  }
}
