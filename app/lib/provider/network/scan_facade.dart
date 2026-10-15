import 'dart:async';

import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Discovers devices in stages, cheapest first: multicast announcement and
/// favorite probes right away, http-based discovery on the subnets only when
/// nothing was confirmed within 1 second.
class StartSmartScan extends AsyncGlobalAction {
  @override
  Future<void> reduce() async {
    final favorites = ref.read(favoritesProvider);
    final settings = ref.read(settingsProvider);
    // Scan every interface the host exposes: capping the list silently drops
    // devices on the other subnets. The staged discovery is cheap (announce +
    // favorites), and the subnet-scan fallback only runs for interfaces where
    // nothing was confirmed.
    final networkInterfaces = ref.read(localIpProvider).localIps.toList();

    await ref
        .redux(nearbyDevicesProvider)
        .dispatchAsync(
          StartStagedScan(
            favorites: favorites,
            interfaces: networkInterfaces,
            port: settings.port,
            https: settings.https,
            grace: const Duration(seconds: 1),
          ),
        );
  }
}

/// HTTP based discovery on a fixed set of subnets.
class StartLegacySubnetScan extends AsyncGlobalAction {
  final List<String> subnets;

  StartLegacySubnetScan({
    required this.subnets,
  });

  @override
  Future<void> reduce() async {
    final settings = ref.read(settingsProvider);
    final port = settings.port;
    final https = settings.https;

    // send announcement in parallel
    ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());

    await Future.wait<void>([
      for (final subnet in subnets) ref.redux(nearbyDevicesProvider).dispatchAsync(StartLegacyScan(port: port, localIp: subnet, https: https)),
    ]);
  }
}
