import 'package:dart_mappable/dart_mappable.dart';
import 'package:uuid/uuid.dart';

part 'sync_share.mapper.dart';

const _uuid = Uuid();

/// One directory the local device shares with the rest of the network.
///
/// Stored as part of the [SyncSharesService] state, and forwarded to the HTTP
/// server as part of [ServerConfigV2.sync_shares] so the `/api/localsend/sync/{id}/*`
/// routes can serve the manifest, tree, and file bodies. The receiver picks
/// the share by `id` when it lists what's available.
@MappableClass()
class SyncShare with SyncShareMappable {
  /// Stable identifier used in URLs (`/api/localsend/sync/{id}/*`) and in the
  /// receiver-side state file (`.localsend-sync/{id}.json`). Never reused.
  final String id;

  /// Human-friendly name shown in the receiver's browse dialog.
  final String name;

  /// Absolute path to the directory the sender shares.
  final String root;

  /// Gitignore-style exclude patterns (forward slashes). Empty when nothing
  /// is excluded; lines starting with `#` are comments.
  final List<String> excludes;

  const SyncShare({
    required this.id,
    required this.name,
    required this.root,
    this.excludes = const [],
  });

  /// Build a fresh share with a new id; used by the "add" action so the
  /// caller does not have to import the uuid package itself.
  factory SyncShare.create({
    required String name,
    required String root,
    List<String> excludes = const [],
  }) {
    return SyncShare(id: _uuid.v4(), name: name, root: root, excludes: excludes);
  }

  static const fromJson = SyncShareMapper.fromJson;
}
