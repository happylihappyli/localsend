// ignore_for_file: prefer_const_constructors_in_immutables

import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';

part 'sync_session.mapper.dart';

/// The seven states of a directory-sync session, as described in
/// `support/sync_design.md` §7. The state is held by
/// [SyncSessionsService] and updated by the actions in
/// `provider/sync/actions.dart`.
///
/// The names are stable on the wire only when serialized to the
/// `partial` / `done` / `failed` snapshots on disk; in-memory the enum is
/// compared by identity.
enum SyncSessionState {
  /// Nothing has happened yet. The session will move to `resolving` as soon
  /// as the user picks which sub-tree to sync.
  idle,

  /// Fetching the remote manifest and computing a plan.
  planning,

  /// There are conflicts in the plan; waiting for the user to resolve them
  /// one by one before any file is moved.
  resolvingConflicts,

  /// Downloading the planned files. Transfers are tracked in
  /// [SyncSession.completedTransfers] / [SyncSession.totalTransfers].
  downloading,

  /// Done; [SyncSession.summary] carries the final counters.
  done,

  /// The user cancelled the session mid-way. Files that already arrived
  /// are kept; nothing is deleted locally.
  cancelled,

  /// The session failed (network error, I/O error, server rejected the
  /// upload, ...). [SyncSession.error] carries the cause.
  failed,
}

extension SyncSessionStateLabel on SyncSessionState {
  /// Human-readable label used in the UI.
  String get label {
    switch (this) {
      case SyncSessionState.idle:
        return 'Idle';
      case SyncSessionState.planning:
        return 'Planning';
      case SyncSessionState.resolvingConflicts:
        return 'Resolving conflicts';
      case SyncSessionState.downloading:
        return 'Downloading';
      case SyncSessionState.done:
        return 'Done';
      case SyncSessionState.cancelled:
        return 'Cancelled';
      case SyncSessionState.failed:
        return 'Failed';
    }
  }
}

/// What the user picked when the plan surfaced a conflict.
enum ConflictResolution {
  /// Take the remote version; the local file is overwritten.
  takeRemote,

  /// Keep the local file; the remote one is skipped for this sync.
  keepLocal,
}

@immutable
@MappableClass()
class ConflictEntry with ConflictEntryMappable {
  final String path;
  final String localSha256;
  final int localSize;
  final int localMtimeUnix;
  final String remoteSha256;
  final int remoteSize;
  final int remoteMtimeUnix;

  const ConflictEntry({
    required this.path,
    required this.localSha256,
    required this.localSize,
    required this.localMtimeUnix,
    required this.remoteSha256,
    required this.remoteSize,
    required this.remoteMtimeUnix,
  });

  static const fromJson = ConflictEntryMapper.fromJson;
}

/// Aggregated counters for a finished or in-progress sync.
///
/// Lives on [SyncSession.summary] and is what the UI renders in the
/// progress dialog. `errors` is non-empty only when the session ended in
/// [SyncSessionState.failed].
@immutable
@MappableClass()
class SyncSummary with SyncSummaryMappable {
  final int downloaded;
  final int skipped;
  final int conflictsResolved;
  final List<String> errors;

  const SyncSummary({
    required this.downloaded,
    required this.skipped,
    required this.conflictsResolved,
    required this.errors,
  });

  static const empty = SyncSummary(
    downloaded: 0,
    skipped: 0,
    conflictsResolved: 0,
    errors: [],
  );

  static const fromJson = SyncSummaryMapper.fromJson;
}

/// In-memory view of a single directory-sync session.
///
/// The session is created by `StartSyncSessionAction` and lives until the
/// user dismisses the dialog or the app is restarted. The persistent
/// counterpart (`.localsend-sync/{id}.json`) is the `SyncState` defined in
/// Rust; that file is owned by the receiver side and is the input the next
/// session uses as `previous_paths`.
@immutable
@MappableClass()
class SyncSession with SyncSessionMappable {
  /// Unique id for this session; used as the key in
  /// [SyncSessionsService.byPeer] and as the receiver-side state file id.
  final String id;

  /// Fingerprint of the peer (sender) the session is talking to. Used to
  /// look up the share on the sender and as the on-disk state key.
  final String peerFingerprint;

  /// The sender-side share id. The receiver uses it to hit
  /// `/api/localsend/sync/{shareId}/...` on the peer.
  final String shareId;

  /// Display name of the share, copied from the sender's announce.
  final String shareName;

  /// Local directory the receiver wants to mirror the share into.
  final String localRoot;

  /// Current state of the session.
  final SyncSessionState state;

  /// Number of files already transferred successfully.
  final int completedTransfers;

  /// Total number of files the plan asked for. 0 while still in
  /// [SyncSessionState.planning].
  final int totalTransfers;

  /// Conflicts that still need a decision. Empty once the user has
  /// answered all of them.
  final List<ConflictEntry> openConflicts;

  /// Last error message, only set in [SyncSessionState.failed].
  final String? error;

  /// Aggregate counters. Set to [SyncSummary.empty] while the session is
  /// still running; populated once the session reaches a terminal state.
  final SyncSummary summary;

  const SyncSession({
    required this.id,
    required this.peerFingerprint,
    required this.shareId,
    required this.shareName,
    required this.localRoot,
    required this.state,
    required this.completedTransfers,
    required this.totalTransfers,
    required this.openConflicts,
    required this.error,
    required this.summary,
  });

  /// Convenience constructor for the start action: a session that has just
  /// been created and is waiting to be planned.
  factory SyncSession.start({
    required String id,
    required String peerFingerprint,
    required String shareId,
    required String shareName,
    required String localRoot,
  }) {
    return SyncSession(
      id: id,
      peerFingerprint: peerFingerprint,
      shareId: shareId,
      shareName: shareName,
      localRoot: localRoot,
      state: SyncSessionState.idle,
      completedTransfers: 0,
      totalTransfers: 0,
      openConflicts: const [],
      error: null,
      summary: SyncSummary.empty,
    );
  }

  /// Like [copyWith] but with a `clearError` knob, because nullable state
  /// fields cannot be told apart from "untouched" by a regular copyWith.
  SyncSession copyState({
    SyncSessionState? state,
    int? completedTransfers,
    int? totalTransfers,
    List<ConflictEntry>? openConflicts,
    SyncSummary? summary,
    String? error,
    bool clearError = false,
  }) {
    return SyncSession(
      id: id,
      peerFingerprint: peerFingerprint,
      shareId: shareId,
      shareName: shareName,
      localRoot: localRoot,
      state: state ?? this.state,
      completedTransfers: completedTransfers ?? this.completedTransfers,
      totalTransfers: totalTransfers ?? this.totalTransfers,
      openConflicts: openConflicts ?? this.openConflicts,
      error: clearError ? null : (error ?? this.error),
      summary: summary ?? this.summary,
    );
  }

  static const fromJson = SyncSessionMapper.fromJson;
}
