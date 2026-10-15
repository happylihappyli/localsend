import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/sync/plan_response.dart';
import 'package:localsend_app/provider/sync/sync_session_provider.dart';
import 'package:localsend_app/provider/sync/sync_session_state.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Centralised "pending conflicts" list.
///
/// The single global sync session (in [syncSessionProvider]) holds the
/// full plan. When the session reaches [SyncPhase.resolvingConflicts]
/// every conflict path in `plan.conflicts` that has no entry in
/// `conflictDecisions` is shown here. The user can:
///
///   - decide per-row (keep local / take remote / keep both / skip),
///   - or use the bulk buttons at the top to apply the same decision
///     to every visible row.
///
/// The default selection is "keep local for every row" — that matches
/// the project rule "B-side wins by default". Tapping "Apply" dispatches
/// [SettleConflictsAction] (through the existing provider action) and
/// the session moves to [SyncPhase.done].
///
/// If the global session is in any other phase this page is read-only
/// (or empty) — there is nothing for the user to act on.
class PendingSyncPage extends StatefulWidget {
  const PendingSyncPage({super.key});

  @override
  State<PendingSyncPage> createState() => _PendingSyncPageState();
}

class _PendingSyncPageState extends State<PendingSyncPage> {
  /// Set of conflict paths the user has selected. Anything selected
  /// is affected by the bulk buttons. Default is empty — only the
  /// single-row "decide" buttons update a row's status.
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final session = context.watch(syncSessionProvider);
    if (session == null || session.plan == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.pendingSyncPage.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.pendingSyncPage.empty.none, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final plan = session.plan!;
    final decisions = session.conflictDecisions;
    final pending = plan.conflicts.where((c) => decisions[c.path] == null).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pendingSyncPage.title),
        actions: [
          if (pending.isNotEmpty)
            TextButton(
              onPressed: _selected.isEmpty ? null : () => _bulkResolve(ConflictResolution.keepLocal),
              child: Text(t.pendingSyncPage.bulk.keepLocal),
            ),
          if (pending.isNotEmpty)
            TextButton(
              onPressed: _selected.isEmpty ? null : () => _bulkResolve(ConflictResolution.keepRemote),
              child: Text(t.pendingSyncPage.bulk.takeRemote),
            ),
          if (pending.isNotEmpty)
            TextButton(
              onPressed: _selected.isEmpty ? null : () => _bulkResolve(ConflictResolution.skip),
              child: Text(t.pendingSyncPage.bulk.skip),
            ),
        ],
      ),
      body: Column(
        children: [
          if (pending.isNotEmpty)
            Container(
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Text(
                    t.pendingSyncPage.summary(pending: pending.length, total: plan.conflicts.length),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selected.length == pending.length ? null : () => setState(() {
                      _selected
                        ..clear()
                        ..addAll(pending.map((c) => c.path));
                    }),
                    child: Text(t.pendingSyncPage.selectAll),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty ? null : () => setState(_selected.clear),
                    child: Text(t.pendingSyncPage.clearSelection),
                  ),
                ],
              ),
            ),
          Expanded(
            child: pending.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 64, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 12),
                          Text(
                            t.pendingSyncPage.empty.resolved,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () async {
                              await context.redux(syncSessionProvider).dispatchAsync(SettleConflictsAction());
                              if (context.mounted) {
                                context.pop();
                              }
                            },
                            icon: const Icon(Icons.check),
                            label: Text(t.pendingSyncPage.apply),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: pending.length,
                    itemBuilder: (context, i) {
                      final c = pending[i];
                      return _ConflictRow(
                        conflict: c,
                        selected: _selected.contains(c.path),
                        onToggleSelect: () => setState(() {
                          if (_selected.contains(c.path)) {
                            _selected.remove(c.path);
                          } else {
                            _selected.add(c.path);
                          }
                        }),
                        onResolve: (decision) async {
                          context.redux(syncSessionProvider).dispatch(
                                ResolveConflictAction(path: c.path, decision: decision),
                              );
                          if (!context.mounted) {
                            return;
                          }
                          setState(() {
                            _selected.remove(c.path);
                          });
                        },
                      );
                    },
                  ),
          ),
          if (pending.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          // Default to "keep local" for the rest of
                          // the un-selected rows so tapping Apply
                          // does not stall on missing decisions.
                          for (final c in pending) {
                            if (decisions[c.path] == null) {
                              context.redux(syncSessionProvider).dispatch(
                                    ResolveConflictAction(path: c.path, decision: ConflictResolution.keepLocal),
                                  );
                            }
                          }
                          if (!context.mounted) {
                            return;
                          }
                          await context.redux(syncSessionProvider).dispatchAsync(SettleConflictsAction());
                          if (context.mounted) {
                            context.pop();
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: Text(t.pendingSyncPage.apply),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _bulkResolve(ConflictResolution decision) {
    if (_selected.isEmpty) {
      return;
    }
    for (final path in _selected) {
      context.redux(syncSessionProvider).dispatch(ResolveConflictAction(path: path, decision: decision));
    }
    setState(_selected.clear);
  }
}
class _ConflictRow extends StatelessWidget {
  final RemoteSyncConflict conflict;
  final bool selected;
  final VoidCallback onToggleSelect;
  final Future<void> Function(ConflictResolution) onResolve;

  const _ConflictRow({
    required this.conflict,
    required this.selected,
    required this.onToggleSelect,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleSelect,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  Checkbox(value: selected, onChanged: (_) => onToggleSelect()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(conflict.path, style: const TextStyle(fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${t.pendingSyncPage.localSize(bytes: conflict.localSize)} · ${_shortSha(conflict.localSha256)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${t.pendingSyncPage.remoteSize(bytes: conflict.remoteSize)} · ${_shortSha(conflict.remoteSha256)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => onResolve(ConflictResolution.keepLocal), child: Text(t.settingsTab.syncConflict.keepLocal)),
                TextButton(onPressed: () => onResolve(ConflictResolution.keepRemote), child: Text(t.settingsTab.syncConflict.keepRemote)),
                TextButton(onPressed: () => onResolve(ConflictResolution.skip), child: Text(t.settingsTab.syncConflict.skip)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortSha(String sha) {
    if (sha.length <= 12) {
      return sha;
    }
    return '${sha.substring(0, 6)}…${sha.substring(sha.length - 6)}';
  }
}
