import 'dart:convert';

import 'package:localsend_app/provider/sync/sync_http_client.dart';

/// Mirrors the on-the-wire `Plan` returned by `POST /sync/{id}/plan`.
///
/// The Rust side is `packages/core/src/sync/mod.rs` `Plan` and the wire
/// format is whatever `serde_json` produces (snake_case fields). v1 only
/// acts on [downloads] and [conflicts]; [uploads] are kept so we can
/// surface them in the UI ("you would push 3 files") without acting on
/// them. [skips] are shown as a single line ("12 files unchanged").
class RemoteSyncPlan {
  final int version;
  final String generatedAt;
  final List<RemoteSyncTransfer> downloads;
  final List<RemoteSyncTransfer> uploads;
  final List<RemoteSyncConflict> conflicts;
  final List<RemoteSyncSkip> skips;

  const RemoteSyncPlan({
    required this.version,
    required this.generatedAt,
    required this.downloads,
    required this.uploads,
    required this.conflicts,
    required this.skips,
  });

  factory RemoteSyncPlan.fromJson(Map<String, dynamic> j) => RemoteSyncPlan(
        version: (j['version'] as num).toInt(),
        generatedAt: j['generated_at'] as String,
        downloads: (j['downloads'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RemoteSyncTransfer.fromJson)
            .toList(growable: false),
        uploads: (j['uploads'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RemoteSyncTransfer.fromJson)
            .toList(growable: false),
        conflicts: (j['conflicts'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RemoteSyncConflict.fromJson)
            .toList(growable: false),
        skips: (j['skips'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RemoteSyncSkip.fromJson)
            .toList(growable: false),
      );
}

/// One file the sender is asking the receiver to fetch or push.
/// The `sha256` is the *expected* hash; v1 does not verify it after the
/// download, so this is informational.
class RemoteSyncTransfer {
  final String path;
  final int size;
  final String sha256;

  const RemoteSyncTransfer({required this.path, required this.size, required this.sha256});

  factory RemoteSyncTransfer.fromJson(Map<String, dynamic> j) => RemoteSyncTransfer(
        path: j['path'] as String,
        size: (j['size'] as num).toInt(),
        sha256: j['sha256'] as String,
      );
}

/// A file where both sides have changed since the last successful sync.
/// The UI lets the user pick one of keep-local / keep-remote / keep-both
/// / skip. v1 never picks a side automatically.
class RemoteSyncConflict {
  final String path;
  final int localMtimeUnix;
  final String localSha256;
  final int localSize;
  final int remoteMtimeUnix;
  final String remoteSha256;
  final int remoteSize;

  const RemoteSyncConflict({
    required this.path,
    required this.localMtimeUnix,
    required this.localSha256,
    required this.localSize,
    required this.remoteMtimeUnix,
    required this.remoteSha256,
    required this.remoteSize,
  });

  factory RemoteSyncConflict.fromJson(Map<String, dynamic> j) => RemoteSyncConflict(
        path: j['path'] as String,
        localMtimeUnix: (j['local_mtime_unix'] as num).toInt(),
        localSha256: j['local_sha256'] as String,
        localSize: (j['local_size'] as num).toInt(),
        remoteMtimeUnix: (j['remote_mtime_unix'] as num).toInt(),
        remoteSha256: j['remote_sha256'] as String,
        remoteSize: (j['remote_size'] as num).toInt(),
      );
}

/// A file the diff decided not to touch, plus why. The receiver surfaces
/// "12 files unchanged" but does not let the user act on skips.
class RemoteSyncSkip {
  final String path;
  final String reason;

  const RemoteSyncSkip({required this.path, required this.reason});

  factory RemoteSyncSkip.fromJson(Map<String, dynamic> j) => RemoteSyncSkip(
        path: j['path'] as String,
        reason: j['reason'] as String,
      );
}

/// Build the JSON body for `POST /sync/{id}/plan`. v1 sends an empty
/// local manifest and no previous paths: we have no sync state yet (that
/// is PR 7) and the user has not pre-selected a local mirror. Every
/// remote file the user picked therefore lands in `downloads` unless
/// the sender's diff flags it as a conflict.
Map<String, dynamic> planRequestBody({required List<RemoteSyncEntry> local, required List<String> previousPaths}) {
  return {
    'previous_paths': previousPaths,
    'local': {
      'version': 1,
      'root': '',
      'generated_at': '',
      'excludes': <String>[],
      'entries': <Map<String, dynamic>>[
        for (final e in local)
          {
            'path': e.path,
            'size': e.size,
            'mtime_unix': e.mtimeUnix,
            'sha256': e.sha256,
            'mode': e.mode,
          },
      ],
    },
  };
}

/// Helper: encode [planRequestBody] as UTF-8 bytes for an HTTP POST.
List<int> encodePlanRequestBody({required List<RemoteSyncEntry> local, required List<String> previousPaths}) {
  return utf8.encode(jsonEncode(planRequestBody(local: local, previousPaths: previousPaths)));
}
