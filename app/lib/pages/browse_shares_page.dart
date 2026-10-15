import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/browse_share_tree_page.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/sync/browse_state.dart';
import 'package:localsend_app/provider/sync/sync_browse_provider.dart';
import 'package:localsend_app/provider/sync/sync_http_client.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Top-level entry point for the B-side flow. Lists every nearby device
/// that exposes at least one directory-sync share and lets the user
/// drill into a share to pick files.
class BrowseSharesPage extends StatefulWidget {
  const BrowseSharesPage({super.key});

  @override
  State<BrowseSharesPage> createState() => _BrowseSharesPageState();
}

class _BrowseSharesPageState extends State<BrowseSharesPage> {
  /// Per-device probe result. `null` means "not yet probed".
  final Map<String, _DeviceShares> _probeResults = {};

  @override
  void initState() {
    super.initState();
    // Kick off probes for every currently-known device. New arrivals
    // also get probed via didChangeDependencies.
    WidgetsBinding.instance.addPostFrameCallback((_) => _probeAll());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-probe when the nearby-device set changes.
    _probeAll();
  }

  void _probeAll() {
    if (!mounted) {
      return;
    }
    final devices = context.ref.read(nearbyDevicesProvider).devices.values;
    for (final d in devices) {
      unawaited(_ensureProbed(d));
    }
  }

  Future<void> _ensureProbed(Device device) async {
    if (_probeResults.containsKey(device.fingerprint)) {
      return;
    }
    final channel = firstHttpChannel(device);
    if (channel == null) {
      setState(() {
        _probeResults[device.fingerprint] = _DeviceShares(
          shares: const [],
          error: 'no http channel',
        );
      });
      return;
    }
    setState(() {
      _probeResults[device.fingerprint] = _DeviceShares(shares: null, error: null);
    });
    try {
      final client = SyncHttpClient(host: channel.host, port: channel.port, useTls: channel.https);
      final shares = await client.listShares();
      if (!mounted) {
        return;
      }
      setState(() {
        _probeResults[device.fingerprint] = _DeviceShares(shares: shares, error: null);
      });
    } on SyncHttpException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _probeResults[device.fingerprint] = _DeviceShares(shares: const [], error: e.toString());
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _probeResults[device.fingerprint] = _DeviceShares(shares: const [], error: e.toString());
      });
    }
  }

  void _openShare(Device device, RemoteSyncShare share) {
    context.ref.redux(syncBrowseProvider).dispatch(
          StartBrowseAction(device: device, share: share),
        );
    unawaited(context.push(() => BrowseShareTreePage(deviceFingerprint: device.fingerprint, shareId: share.id)));
  }

  @override
  Widget build(BuildContext context) {
    final devices = context.ref.watch(nearbyDevicesProvider).devices.values.toList()
      ..sort((a, b) => a.alias.compareTo(b.alias));

    // Group device -> list of shares. Devices with no probed shares yet
    // show a "probing" tile; devices whose probe returned an empty list
    // are hidden (they're not contributing anything).
    final sections = <_DeviceSection>[];
    for (final d in devices) {
      final r = _probeResults[d.fingerprint];
      if (r == null) {
        // Still probing.
        sections.add(_DeviceSection(device: d, shares: null, error: null));
        continue;
      }
      if (r.shares == null) {
        // Probe in flight.
        sections.add(_DeviceSection(device: d, shares: null, error: null));
        continue;
      }
      if (r.shares!.isEmpty) {
        // Skip silent devices. They only add noise to the list.
        continue;
      }
      sections.add(_DeviceSection(device: d, shares: r.shares!, error: r.error));
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTab.browseShares.title)),
      body: SafeArea(
        child: sections.isEmpty
            ? const _EmptyState()
            : RefreshIndicator(
                onRefresh: () async {
                  setState(_probeResults.clear);
                  _probeAll();
                },
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  itemCount: sections.length,
                  itemBuilder: (context, i) => _DeviceSectionTile(section: sections[i], onShareTap: _openShare),
                ),
              ),
      ),
    );
  }
}

class _DeviceShares {
  /// `null` while the probe is in flight, an empty list when the
  /// device has no shares, otherwise the list of shares.
  final List<RemoteSyncShare>? shares;
  final String? error;

  const _DeviceShares({required this.shares, required this.error});
}

class _DeviceSection {
  final Device device;
  final List<RemoteSyncShare>? shares; // null = still probing
  final String? error;

  const _DeviceSection({required this.device, required this.shares, required this.error});
}

class _DeviceSectionTile extends StatelessWidget {
  final _DeviceSection section;
  final void Function(Device, RemoteSyncShare) onShareTap;

  const _DeviceSectionTile({required this.section, required this.onShareTap});

  @override
  Widget build(BuildContext context) {
    final d = section.device;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.devices),
              title: Text(d.alias, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                section.error == null
                    ? (d.fingerprint.isEmpty ? '' : d.fingerprint.substring(0, d.fingerprint.length.clamp(0, 12)))
                    : t.settingsTab.browseShares.probeError(
                        alias: d.alias,
                        error: section.error!,
                      ),
                style: TextStyle(color: section.error == null ? null : Theme.of(context).colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (section.shares == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: LinearProgressIndicator(),
              )
            else
              for (final s in section.shares!)
                ListTile(
                  leading: const Icon(Icons.folder_shared),
                  title: Text(s.name),
                  trailing: Text(t.settingsTab.browseShares.openShare),
                  onTap: () => onShareTap(d, s),
                ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              t.settingsTab.browseShares.empty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
