import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/sync_share.dart';
import 'package:localsend_app/pages/dialogs/share_directory_dialog.dart';
import 'package:localsend_app/provider/sync/sync_shares_provider.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Lists every directory the local device is currently sharing, with
/// "add" / "edit" / "remove" actions. The page is a thin wrapper around
/// [ShareDirectoryDialog]: the dialog collects input, this page decides
/// which [Redux] action to dispatch based on the sealed
/// [ShareDialogResult] returned.
class SyncSharesPage extends StatelessWidget {
  const SyncSharesPage({super.key});

  Future<void> _openDialog(BuildContext context, {SyncShare? existing}) async {
    final ref = context.ref;
    final result = await ShareDirectoryDialog.show(context, existing: existing);
    if (result == null) {
      return;
    }
    switch (result) {
      case ShareDialogCancelled():
        return;
      case ShareDialogSaved(:final share):
        // Whether the dialog was opened in add or edit mode is
        // already encoded in `share.id`: a brand-new id means "add",
        // an existing id means "update". So we route by id.
        final isNew = ref.read(syncSharesProvider).indexWhere((s) => s.id == share.id) == -1;
        if (isNew) {
          await ref.redux(syncSharesProvider).dispatchAsync(
                AddSyncShareAction(
                  name: share.name,
                  root: share.root,
                  excludes: share.excludes,
                ),
              );
        } else {
          await ref.redux(syncSharesProvider).dispatchAsync(
                UpdateSyncShareAction(
                  id: share.id,
                  name: share.name,
                  root: share.root,
                  excludes: share.excludes,
                ),
              );
        }
      case ShareDialogRemoved(:final id):
        await ref.redux(syncSharesProvider).dispatchAsync(RemoveSyncShareAction(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTab.syncShares.title)),
      body: SafeArea(
        child: Consumer(
          builder: (context, ref) {
            final shares = ref.watch(syncSharesProvider);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    t.settingsTab.syncShares.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: shares.isEmpty
                      ? _EmptyState(onAdd: () => _openDialog(context))
                      : ResponsiveListView(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
                          children: [
                            for (final share in shares)
                              _ShareTile(
                                share: share,
                                onTap: () => _openDialog(context, existing: share),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(context),
        icon: const Icon(Icons.add),
        label: Text(t.settingsTab.syncShares.add),
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  final SyncShare share;
  final VoidCallback onTap;

  const _ShareTile({required this.share, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.folder_shared),
        title: Text(share.name, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              share.root,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            if (share.excludes.isNotEmpty)
              Text(
                '${share.excludes.length} exclude${share.excludes.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              t.settingsTab.syncShares.empty(add: t.settingsTab.syncShares.add),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(t.settingsTab.syncShares.add),
            ),
          ],
        ),
      ),
    );
  }
}
