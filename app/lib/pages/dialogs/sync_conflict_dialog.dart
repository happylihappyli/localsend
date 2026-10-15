import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/sync/plan_response.dart';
import 'package:localsend_app/provider/sync/sync_session_state.dart';

/// Modal that asks the user how to settle one [RemoteSyncConflict].
///
/// The four options mirror spec §9 "B 端冲突解决":
///
/// - Keep local: do nothing, the local file wins.
/// - Keep remote: overwrite the local file with the sender's version.
/// - Keep both: write the sender's version next to the local one as
///   `<path>.remote` so the user can compare them by hand.
/// - Skip: do nothing, but flag the path as skipped (no overwrite).
///
/// Returns the picked [ConflictResolution] (or `null` if dismissed).
class SyncConflictDialog extends StatelessWidget {
  final RemoteSyncConflict conflict;
  final int remaining;

  const SyncConflictDialog({required this.conflict, required this.remaining, super.key});

  static Future<ConflictResolution?> show(
    BuildContext context, {
    required RemoteSyncConflict conflict,
    required int remaining,
  }) {
    return showDialog<ConflictResolution>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SyncConflictDialog(conflict: conflict, remaining: remaining),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = _FileInfo(
      size: conflict.localSize,
      mtimeUnix: conflict.localMtimeUnix,
      sha: conflict.localSha256,
      label: t.settingsTab.syncConflict.localLabel,
    );
    final remote = _FileInfo(
      size: conflict.remoteSize,
      mtimeUnix: conflict.remoteMtimeUnix,
      sha: conflict.remoteSha256,
      label: t.settingsTab.syncConflict.remoteLabel,
    );
    return AlertDialog(
      title: Text(t.settingsTab.syncConflict.title(path: conflict.path)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FileRow(info: local),
          const SizedBox(height: 8),
          _FileRow(info: remote),
          const SizedBox(height: 16),
          Text(
            t.settingsTab.syncConflict.remaining(count: remaining),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictResolution.keepLocal),
          child: Text(t.settingsTab.syncConflict.keepLocal),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictResolution.keepBoth),
          child: Text(t.settingsTab.syncConflict.keepBoth),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ConflictResolution.keepRemote),
          child: Text(t.settingsTab.syncConflict.keepRemote),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictResolution.skip),
          child: Text(t.settingsTab.syncConflict.skip),
        ),
      ],
    );
  }
}

class _FileInfo {
  final String label;
  final int size;
  final int mtimeUnix;
  final String sha;

  const _FileInfo({required this.label, required this.size, required this.mtimeUnix, required this.sha});
}

class _FileRow extends StatelessWidget {
  final _FileInfo info;
  const _FileRow({required this.info});

  @override
  Widget build(BuildContext context) {
    final mtime = DateTime.fromMillisecondsSinceEpoch(info.mtimeUnix * 1000, isUtc: true).toLocal();
    final mtimeStr =
        '${mtime.year.toString().padLeft(4, '0')}-${mtime.month.toString().padLeft(2, '0')}-${mtime.day.toString().padLeft(2, '0')} '
        '${mtime.hour.toString().padLeft(2, '0')}:${mtime.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(info.label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('${_formatSize(info.size)}  ·  $mtimeStr', style: Theme.of(context).textTheme.bodySmall),
        Text(info.sha, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      ],
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}
