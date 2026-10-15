import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/pending_sync_page.dart';
import 'package:localsend_app/provider/sync/browse_state.dart';
import 'package:localsend_app/provider/sync/sync_session_provider.dart';
import 'package:localsend_app/provider/sync/sync_session_state.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// The "B 端同步进度" page. Owns the [StartSyncAction] lifetime: the
/// page dispatches it on first build, drives the user through conflict
/// resolution, and finally dispatches [ResetSyncAction] when dismissed.
class SyncSessionPage extends StatefulWidget {
  /// Snapshot of the user's pick. Pulled from [syncBrowseProvider] and
  /// passed in as plain data so the page can outlive a pop of the
  /// browse screen if needed.
  final BrowseState browse;

  const SyncSessionPage({required this.browse, super.key});

  @override
  State<SyncSessionPage> createState() => _SyncSessionPageState();
}

class _SyncSessionPageState extends State<SyncSessionPage> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Dispatched from a post-frame so the provider is listening before
    // the first state emission. unawaited() silences the
    // `discarded_futures` lint for the fire-and-forget async action.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started || !mounted) {
        return;
      }
      _started = true;
      unawaited(context.ref.redux(syncSessionProvider).dispatchAsync(StartSyncAction(browse: widget.browse)));
    });
  }

  void _dismiss() {
    context.ref.redux(syncSessionProvider).dispatch(ResetSyncAction());
    context.pop();
  }

  void _cancel() {
    context.ref.redux(syncSessionProvider).dispatch(CancelSyncAction());
  }

  Future<void> _openPendingDecisions() async {
    // Conflicts are now handled in a single centralised list page
    // ([PendingSyncPage]). The session state is held by the global
    // [syncSessionProvider], so we just navigate — the user can leave
    // and come back via the contacts-page badge without losing the
    // plan.
    await context.push(() => const PendingSyncPage());
  }

  @override
  Widget build(BuildContext context) {
    final session = context.ref.watch(syncSessionProvider);
    return PopScope(
      canPop: session?.isActive != true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          // PopScope already let us through, so the session must be in
          // a terminal phase — clean up the global state.
          _dismiss();
          return;
        }
        // Confirm before backing out of an active session.
        if (session?.isActive != true) {
          _dismiss();
          if (context.mounted) {
            // routerino's pop() is sync; PopScope already prevented the
            // platform pop, so we drive the navigation ourselves.
            context.pop();
          }
          return;
        }
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(t.settingsTab.syncSession.cancelTitle),
            content: Text(t.settingsTab.syncSession.cancelBody),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.general.cancel)),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(t.settingsTab.syncSession.cancelConfirm)),
            ],
          ),
        );
        if (ok == true) {
          _cancel();
          _dismiss();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.settingsTab.syncSession.title(alias: widget.browse.device.alias, share: widget.browse.share.name)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (session?.isActive == true) {
                _cancel();
                _dismiss();
              } else {
                _dismiss();
              }
            },
          ),
        ),
        body: SafeArea(child: _buildBody(context, session)),
        bottomNavigationBar: _buildBottomBar(context, session),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SyncSessionState? session) {
    if (session == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(t.settingsTab.syncSession.preparing),
          ],
        ),
      );
    }
    switch (session.phase) {
      case SyncPhase.idle:
      case SyncPhase.fetchingManifest:
      case SyncPhase.submittingPlan:
        return _ProgressPanel(label: t.settingsTab.syncSession.contacting);
      case SyncPhase.downloading:
        return _DownloadingView(session: session);
      case SyncPhase.resolvingConflicts:
        return _ConflictsView(session: session, onResolve: _openPendingDecisions);
      case SyncPhase.done:
        return _DoneView(session: session);
      case SyncPhase.failed:
        return _FailedView(session: session);
      case SyncPhase.cancelled:
        return _CancelledView(session: session);
    }
  }

  Widget? _buildBottomBar(BuildContext context, SyncSessionState? session) {
    if (session == null) {
      return null;
    }
    if (session.isActive) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: OutlinedButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.stop),
            label: Text(t.settingsTab.syncSession.cancel),
          ),
        ),
      );
    }
    if (session.isComplete || session.isFailed || session.isCancelled) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _dismiss,
            icon: const Icon(Icons.check),
            label: Text(t.settingsTab.syncSession.dismiss),
          ),
        ),
      );
    }
    return null;
  }
}

class _ProgressPanel extends StatelessWidget {
  final String label;
  const _ProgressPanel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }
}

class _DownloadingView extends StatelessWidget {
  final SyncSessionState session;
  const _DownloadingView({required this.session});

  @override
  Widget build(BuildContext context) {
    final plan = session.plan!;
    final total = plan.downloads.length;
    final done = session.downloadedCount;
    final failed = session.failedCount;
    final pending = session.pendingCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            t.settingsTab.syncSession.progress(
              done: done,
              total: total,
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(value: total == 0 ? 0 : done / total),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            t.settingsTab.syncSession.remaining(count: pending),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (failed > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              t.settingsTab.syncSession.failedShort(count: failed),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: plan.downloads.length,
            itemBuilder: (context, i) {
              final d = plan.downloads[i];
              final status = session.fileStatus[d.path] ?? FileSyncStatus.pending;
              return _FileTile(path: d.path, size: d.size, status: status);
            },
          ),
        ),
      ],
    );
  }
}

class _ConflictsView extends StatelessWidget {
  final SyncSessionState session;
  final VoidCallback onResolve;

  const _ConflictsView({required this.session, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final plan = session.plan!;
    final pending = plan.conflicts.where((c) => !session.conflictDecisions.containsKey(c.path)).length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.folder_shared,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              t.settingsTab.syncSession.conflictsHeader(count: plan.conflicts.length),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              t.settingsTab.syncSession.conflictsPending(count: pending),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(
              t.settingsTab.syncSession.actionHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onResolve,
              icon: const Icon(Icons.list_alt),
              label: Text(t.settingsTab.syncSession.actionButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  final SyncSessionState session;
  const _DoneView({required this.session});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(t.settingsTab.syncSession.done, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          _SummaryRow(label: t.settingsTab.syncSession.downloaded, value: session.downloadedCount),
          _SummaryRow(label: t.settingsTab.syncSession.skipped, value: session.skippedCount),
          if (session.failedCount > 0) _SummaryRow(label: t.settingsTab.syncSession.failed, value: session.failedCount),
        ],
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  final SyncSessionState session;
  const _FailedView({required this.session});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(t.settingsTab.syncSession.failedHeader, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            session.error ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }
}

class _CancelledView extends StatelessWidget {
  final SyncSessionState session;
  const _CancelledView({required this.session});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cancel_outlined, size: 64, color: Theme.of(context).disabledColor),
          const SizedBox(height: 16),
          Text(t.settingsTab.syncSession.cancelled, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          _SummaryRow(label: t.settingsTab.syncSession.downloaded, value: session.downloadedCount),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final String path;
  final int size;
  final FileSyncStatus status;
  const _FileTile({required this.path, required this.size, required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      FileSyncStatus.pending => (Icons.hourglass_empty, null),
      FileSyncStatus.downloading => (Icons.downloading, Theme.of(context).colorScheme.primary),
      FileSyncStatus.done => (Icons.check_circle, Theme.of(context).colorScheme.primary),
      FileSyncStatus.failed => (Icons.error_outline, Theme.of(context).colorScheme.error),
      FileSyncStatus.skipped => (Icons.skip_next, Theme.of(context).disabledColor),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(_formatSize(size), style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$value', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

String _formatSize(int bytes) {
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
