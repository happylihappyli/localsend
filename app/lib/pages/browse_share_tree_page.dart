import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/sync_session_page.dart';
import 'package:localsend_app/provider/sync/browse_state.dart';
import 'package:localsend_app/provider/sync/sync_browse_provider.dart';
import 'package:localsend_app/provider/sync/sync_http_client.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// B-side file picker. Given a remote share, the user picks a local
/// target directory and a subset of files/directories to mirror. The
/// page never talks to the filesystem directly; it only asks the
/// [SyncHttpClient] for the share's manifest and renders that.
class BrowseShareTreePage extends StatefulWidget {
  final String deviceFingerprint;
  final String shareId;

  const BrowseShareTreePage({
    required this.deviceFingerprint,
    required this.shareId,
    super.key,
  });

  @override
  State<BrowseShareTreePage> createState() => _BrowseShareTreePageState();
}

class _BrowseShareTreePageState extends State<BrowseShareTreePage> {
  RemoteSyncManifest? _manifest;
  String? _manifestError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadManifest());
  }

  Future<void> _loadManifest() async {
    final browse = context.ref.read(syncBrowseProvider)[browseKey(
      BrowseKey(deviceFingerprint: widget.deviceFingerprint, shareId: widget.shareId),
    )];
    if (browse == null) {
      setState(() {
        _loading = false;
        _manifestError = 'browse session missing';
      });
      return;
    }
    final channel = firstHttpChannel(browse.device);
    if (channel == null) {
      setState(() {
        _loading = false;
        _manifestError = 'no http channel';
      });
      return;
    }
    setState(() {
      _loading = true;
      _manifestError = null;
    });
    try {
      final client = SyncHttpClient(host: channel.host, port: channel.port, useTls: channel.https);
      final m = await client.getManifest(browse.share.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _manifest = m;
        _loading = false;
      });
    } on SyncHttpException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _manifestError = e.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _manifestError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickTarget() async {
    final path = await pickDirectoryPath();
    if (path == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    context.ref.redux(syncBrowseProvider).dispatch(
          SetBrowseTargetRootAction(
            deviceFingerprint: widget.deviceFingerprint,
            shareId: widget.shareId,
            targetRoot: path,
          ),
        );
  }

  void _toggleAll(bool select) {
    final m = _manifest;
    if (m == null) {
      return;
    }
    // We expose the toggle-all at the root level, which means selecting
    // the entire manifest. The list is built from entries directly.
    final paths = m.entries.where((e) => e.isRegularFile).map((e) => e.path).toList(growable: false);
    for (final p in paths) {
      context.ref.redux(syncBrowseProvider).dispatch(
            ToggleBrowsePathAction(
              deviceFingerprint: widget.deviceFingerprint,
              shareId: widget.shareId,
              path: p,
              selected: select,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final browse = context.ref.watch(syncBrowseProvider)[browseKey(
      BrowseKey(deviceFingerprint: widget.deviceFingerprint, shareId: widget.shareId),
    )];

    if (browse == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Browse session missing')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.settingsTab.browseTree.title(share: browse.share.name),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MetaPanel(browse: browse, onPickTarget: _pickTarget),
            const Divider(height: 1),
            Expanded(
              child: _buildBody(browse),
            ),
          ],
        ),
      ),
      bottomNavigationBar: browse.isReady
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: () {
                    // PR 6: hand off to the sync session. The session
                    // owns its own lifecycle (StartSyncAction dispatches
                    // on first build; conflicts are resolved in-page).
                    // We dispatch EndBrowseAction *after* navigation so
                    // the browse state stays available for the session
                    // page to read while it lives.
                    unawaited(context.push(() => SyncSessionPage(browse: browse)));
                  },
                  icon: const Icon(Icons.sync),
                  label: Text(t.settingsTab.browseTree.start),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(BrowseState browse) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(t.settingsTab.browseTree.loadingTree),
          ],
        ),
      );
    }
    if (_manifestError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            t.settingsTab.browseTree.treeError(path: '/', error: _manifestError!),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final m = _manifest!;
    final files = m.entries.where((e) => e.isRegularFile).toList();
    if (files.isEmpty) {
      return Center(child: Text(t.settingsTab.browseTree.targetPlaceholder));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => _toggleAll(true),
                icon: const Icon(Icons.select_all),
                label: Text(t.settingsTab.browseTree.selectAll),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _toggleAll(false),
                icon: const Icon(Icons.deselect),
                label: Text(t.settingsTab.browseTree.deselectAll),
              ),
              const Spacer(),
              Text(t.settingsTab.browseTree.itemsSelected(count: browse.selectedPaths.length)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, i) {
              final entry = files[i];
              final selected = browse.selectedPaths.contains(entry.path);
              return CheckboxListTile(
                value: selected,
                onChanged: (v) {
                  context.ref.redux(syncBrowseProvider).dispatch(
                        ToggleBrowsePathAction(
                          deviceFingerprint: widget.deviceFingerprint,
                          shareId: widget.shareId,
                          path: entry.path,
                          selected: v,
                        ),
                      );
                },
                title: Text(entry.path),
                subtitle: Text(_formatSize(entry.size)),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
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

class _MetaPanel extends StatelessWidget {
  final BrowseState browse;
  final VoidCallback onPickTarget;

  const _MetaPanel({required this.browse, required this.onPickTarget});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.settingsTab.browseTree.from(alias: browse.device.alias),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  browse.targetRoot == null
                      ? t.settingsTab.browseTree.targetPlaceholder
                      : t.settingsTab.browseTree.target(path: browse.targetRoot!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: browse.targetRoot == null
                        ? Theme.of(context).hintColor
                        : Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onPickTarget,
                icon: const Icon(Icons.folder_open),
                label: Text(t.settingsTab.browseTree.pickTarget),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
