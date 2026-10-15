import 'package:localsend_app/model/persistence/sync_contact.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Persisted list of devices that have ever shared a directory with us
/// (or were added by hand). The contact page watches this and surfaces
/// the "paired" row vs the "nearby" row. The home page watches the
/// pending-conflict count, which is computed from this state plus
/// `syncSessionsProvider`.
///
/// Key invariant: `contact.id == peer fingerprint`. The same physical
/// machine keeps a single row even as its IP, port, or alias change.
final syncContactProvider = ReduxProvider<SyncContactService, List<SyncContact>>((ref) {
  return SyncContactService(ref.read(persistenceProvider));
});

class SyncContactService extends ReduxNotifier<List<SyncContact>> {
  final PersistenceService _persistence;

  SyncContactService(this._persistence);

  @override
  List<SyncContact> init() => _persistence.getSyncContacts();
}

/// Adds a contact or updates an existing one in place (matched by
/// fingerprint). When a contact with the same `id` already exists we
/// preserve `customAlias` and `trusted` so the user's choices survive
/// re-discovery after an IP change.
class UpsertSyncContactAction extends AsyncReduxAction<SyncContactService, List<SyncContact>> {
  final SyncContact contact;
  final bool seenNow;

  UpsertSyncContactAction(this.contact, {this.seenNow = true});

  @override
  Future<List<SyncContact>> reduce() async {
    final existingIndex = state.indexWhere((c) => c.id == contact.id);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    SyncContact merged;
    if (existingIndex == -1) {
      merged = seenNow ? contact.copyWith(lastSeenUnix: now) : contact;
    } else {
      final existing = state[existingIndex];
      // Don't clobber a user-set alias with the auto-discovered one.
      final alias = existing.customAlias ? existing.alias : (contact.alias.isNotEmpty ? contact.alias : existing.alias);
      merged = existing.copyWith(
        ip: contact.ip ?? existing.ip,
        port: contact.port ?? existing.port,
        alias: alias,
        lastSeenUnix: seenNow ? now : existing.lastSeenUnix,
      );
    }

    final updated = List<SyncContact>.unmodifiable([
      ...state.where((c) => c.id != contact.id),
      merged,
    ]);
    await notifier._persistence.setSyncContacts(updated);
    return updated;
  }
}

/// Marks a contact as trusted (caller is responsible for showing the
/// fingerprint confirmation dialog first).
class TrustSyncContactAction extends AsyncReduxAction<SyncContactService, List<SyncContact>> {
  final String fingerprint;
  final bool trusted;

  TrustSyncContactAction({required this.fingerprint, required this.trusted});

  @override
  Future<List<SyncContact>> reduce() async {
    final index = state.indexWhere((c) => c.id == fingerprint);
    if (index == -1) {
      return state;
    }
    final updated = List<SyncContact>.unmodifiable([
      ...state,
    ]..replaceRange(index, index + 1, [state[index].copyWith(trusted: trusted)]));
    await notifier._persistence.setSyncContacts(updated);
    return updated;
  }
}

/// Renames a contact. When [custom] is true, the alias is marked
/// `customAlias` and will not be overwritten by future auto-discoveries.
class RenameSyncContactAction extends AsyncReduxAction<SyncContactService, List<SyncContact>> {
  final String fingerprint;
  final String alias;
  final bool custom;

  RenameSyncContactAction({required this.fingerprint, required this.alias, this.custom = true});

  @override
  Future<List<SyncContact>> reduce() async {
    if (alias.isEmpty) {
      return state;
    }
    final index = state.indexWhere((c) => c.id == fingerprint);
    if (index == -1) {
      return state;
    }
    final updated = List<SyncContact>.unmodifiable([
      ...state,
    ]..replaceRange(
        index,
        index + 1,
        [state[index].copyWith(alias: alias, customAlias: custom)],
      ));
    await notifier._persistence.setSyncContacts(updated);
    return updated;
  }
}

/// Removes a contact row entirely. Any sync subscription pointing at
/// it must be removed by the caller (typically a confirmation dialog).
class RemoveSyncContactAction extends AsyncReduxAction<SyncContactService, List<SyncContact>> {
  final String fingerprint;

  RemoveSyncContactAction(this.fingerprint);

  @override
  Future<List<SyncContact>> reduce() async {
    final updated = state.where((c) => c.id != fingerprint).toList(growable: false);
    if (updated.length == state.length) {
      return state;
    }
    await notifier._persistence.setSyncContacts(updated);
    return List<SyncContact>.unmodifiable(updated);
  }
}

/// Marks every contact that hasn't been seen for [olderThan] as stale.
/// Called once at app start to keep the "nearby" section meaningful
/// after the laptop has been asleep for a week.
class PruneStaleSyncContactsAction extends AsyncReduxAction<SyncContactService, List<SyncContact>> {
  final Duration olderThan;

  PruneStaleSyncContactsAction({this.olderThan = const Duration(days: 7)});

  @override
  Future<List<SyncContact>> reduce() async {
    final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch ~/ 1000;
    // Trusted contacts are never pruned — losing a hand-paired contact
    // because the laptop was closed is the kind of papercut that
    // erodes trust in the app.
    final keep = state.where((c) => c.trusted || (c.lastSeenUnix ?? 0) >= cutoff).toList(growable: false);
    if (keep.length == state.length) {
      return state;
    }
    await notifier._persistence.setSyncContacts(keep);
    return List<SyncContact>.unmodifiable(keep);
  }
}
