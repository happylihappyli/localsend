import 'package:flutter/foundation.dart';
import 'package:localsend_app/provider/sync/sync_http_client.dart';
import 'package:localsend_isolates/model/device.dart';

/// State of the "browse and pick" flow for one remote share.
///
/// Each browsing session is keyed by [browseKey] (a stable identifier
/// derived from device fingerprint + share id). The same device may
/// expose multiple shares and the same share id may appear on multiple
/// devices, so the key includes both.
///
/// The receiver picks [targetRoot] on the local filesystem and a set of
/// [selectedPaths] inside the remote share. The two are independent:
/// targetRoot lives on the receiver, selectedPaths are forward-slash
/// paths relative to the sender's share root.
@immutable
class BrowseState {
  /// The full sender record, including every channel we discovered it
  /// on. The browse flow only ever needs one channel to talk to the
  /// server, but we keep the full object around so the UI can show the
  /// same alias + fingerprint the user already saw on the device list.
  final Device device;

  /// The share on the sender side.
  final RemoteSyncShare share;

  /// Local directory the receiver wants to mirror into. `null` until
  /// the user picks one.
  final String? targetRoot;

  /// Forward-slash paths relative to the share root that the user has
  /// ticked. Files and directories are both represented by their
  /// relative path; directories mean "everything underneath".
  final Set<String> selectedPaths;

  const BrowseState({
    required this.device,
    required this.share,
    this.targetRoot,
    this.selectedPaths = const {},
  });

  BrowseState copyWith({
    String? targetRoot,
    Set<String>? selectedPaths,
  }) {
    return BrowseState(
      device: device,
      share: share,
      targetRoot: targetRoot ?? this.targetRoot,
      selectedPaths: selectedPaths ?? this.selectedPaths,
    );
  }

  /// True when the user has both picked a target root and chosen at
  /// least one path. The "start sync" button is gated on this.
  bool get isReady => targetRoot != null && selectedPaths.isNotEmpty;
}

/// The first HTTP channel we can use to talk to the device. The browse
/// flow only needs a single working channel; the rest are still on
/// [BrowseState.device] for display.
HttpChannel? firstHttpChannel(Device d) {
  for (final c in d.channels) {
    if (c is HttpChannel) {
      return c;
    }
  }
  return null;
}

/// Key under which a [BrowseState] is stored.
@immutable
class BrowseKey {
  final String deviceFingerprint;
  final String shareId;

  const BrowseKey({required this.deviceFingerprint, required this.shareId});

  @override
  bool operator ==(Object other) =>
      other is BrowseKey && other.deviceFingerprint == deviceFingerprint && other.shareId == shareId;

  @override
  int get hashCode => Object.hash(deviceFingerprint, shareId);
}

String browseKey(BrowseKey k) => '${k.deviceFingerprint}/${k.shareId}';
