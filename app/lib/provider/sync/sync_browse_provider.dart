import 'package:localsend_app/provider/sync/browse_state.dart';
import 'package:localsend_app/provider/sync/sync_http_client.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Tracks every in-progress "browse a remote share" session.
///
/// One entry per (device, share) pair. The provider is intentionally
/// flat: a new [StartBrowseAction] replaces any existing entry with the
/// same key, so reopening a share from the device list just shows the
/// current selection.
final syncBrowseProvider = ReduxProvider<SyncBrowseService, Map<String, BrowseState>>((ref) {
  return SyncBrowseService();
});

class SyncBrowseService extends ReduxNotifier<Map<String, BrowseState>> {
  @override
  Map<String, BrowseState> init() => const {};
}

/// Starts a new browsing session for `(device, share)`. Replaces any
/// previous session with the same key.
class StartBrowseAction extends ReduxAction<SyncBrowseService, Map<String, BrowseState>> {
  final Device device;
  final RemoteSyncShare share;

  StartBrowseAction({required this.device, required this.share});

  @override
  Map<String, BrowseState> reduce() {
    final key = browseKey(BrowseKey(deviceFingerprint: device.fingerprint, shareId: share.id));
    final next = BrowseState(device: device, share: share);
    return Map<String, BrowseState>.unmodifiable(<String, BrowseState>{...state, key: next});
  }
}

/// Replaces the target root (the local directory the receiver wants to
/// mirror the chosen files into).
class SetBrowseTargetRootAction extends ReduxAction<SyncBrowseService, Map<String, BrowseState>> {
  final String deviceFingerprint;
  final String shareId;
  final String targetRoot;

  SetBrowseTargetRootAction({
    required this.deviceFingerprint,
    required this.shareId,
    required this.targetRoot,
  });

  @override
  Map<String, BrowseState> reduce() {
    final key = browseKey(BrowseKey(deviceFingerprint: deviceFingerprint, shareId: shareId));
    final existing = state[key];
    if (existing == null) {
      return state;
    }
    final updated = state.map(
      (k, v) => k == key ? MapEntry(k, v.copyWith(targetRoot: targetRoot)) : MapEntry(k, v),
    );
    return Map<String, BrowseState>.unmodifiable(updated);
  }
}

/// Toggles a single path in the current selection. When [selected] is
/// `null` the entry is flipped; when it is `true`/`false` it is forced.
class ToggleBrowsePathAction extends ReduxAction<SyncBrowseService, Map<String, BrowseState>> {
  final String deviceFingerprint;
  final String shareId;
  final String path;
  final bool? selected;

  ToggleBrowsePathAction({
    required this.deviceFingerprint,
    required this.shareId,
    required this.path,
    this.selected,
  });

  @override
  Map<String, BrowseState> reduce() {
    final key = browseKey(BrowseKey(deviceFingerprint: deviceFingerprint, shareId: shareId));
    final existing = state[key];
    if (existing == null) {
      return state;
    }
    final next = {...existing.selectedPaths};
    final want = selected ?? !(next.contains(path));
    if (want) {
      next.add(path);
    } else {
      next.remove(path);
    }
    final updated = state.map(
      (k, v) => k == key ? MapEntry(k, v.copyWith(selectedPaths: next)) : MapEntry(k, v),
    );
    return Map<String, BrowseState>.unmodifiable(updated);
  }
}

/// Drops the session once the user has confirmed or cancelled.
class EndBrowseAction extends ReduxAction<SyncBrowseService, Map<String, BrowseState>> {
  final String deviceFingerprint;
  final String shareId;

  EndBrowseAction({required this.deviceFingerprint, required this.shareId});

  @override
  Map<String, BrowseState> reduce() {
    final key = browseKey(BrowseKey(deviceFingerprint: deviceFingerprint, shareId: shareId));
    if (!state.containsKey(key)) {
      return state;
    }
    final next = Map<String, BrowseState>.from(state)..remove(key);
    return Map<String, BrowseState>.unmodifiable(next);
  }
}
