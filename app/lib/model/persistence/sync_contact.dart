import 'package:dart_mappable/dart_mappable.dart';

part 'sync_contact.mapper.dart';

/// A peer device that has either been auto-discovered via multicast and
/// answered our probe with at least one sync share, or been added manually
/// by the user.
///
/// The key invariant is `id == peer fingerprint` — that way the same
/// physical machine keeps a single contact row even as its IP, port, or
/// display name change. Persisted via [SyncContactsNotifier] in
/// `~/.localsend/sync-contacts.json` (encoded through the
/// `ls_sync_contacts` SharedPreferences key).
///
/// The WeChat-style contact page treats contacts as "paired" by default
/// (tapping opens a 3-tab detail view). A contact becomes "unpaired"
/// when [trusted] is false AND it has only been seen once — the
/// nearby section of the list shows those.
@MappableClass()
class SyncContact with SyncContactMappable {
  /// Peer fingerprint (stable across IP changes). Acts as the primary key.
  final String id;

  /// Last known IPv4/IPv6 address. May be `null` if the device is offline
  /// or has not been seen since startup.
  final String? ip;

  /// Last known sync server port. `null` until the first successful probe.
  final int? port;

  /// Display name. The user can override the auto-discovered alias.
  final String alias;

  /// `true` if the alias was edited by the user (and should not be
  /// auto-updated when the peer's announce arrives with a new alias).
  final bool customAlias;

  /// `true` once the user has explicitly accepted this peer's fingerprint
  /// in the trust dialog. Until then the contact row is read-only.
  final bool trusted;

  /// Last time we saw this peer (Unix seconds). `null` for manually added
  /// contacts that have never been online.
  final int? lastSeenUnix;

  const SyncContact({
    required this.id,
    this.ip,
    this.port,
    required this.alias,
    this.customAlias = false,
    this.trusted = false,
    this.lastSeenUnix,
  });

  factory SyncContact.fromValues({
    required String fingerprint,
    String? ip,
    int? port,
    required String alias,
  }) {
    return SyncContact(
      id: fingerprint,
      ip: ip,
      port: port,
      alias: alias,
      customAlias: false,
    );
  }

  /// Human-readable fingerprint (uppercase hex, colon-separated) for
  /// the trust dialog. Mirrors what the server sends in the Register
  /// event.
  String get fingerprintDisplay {
    final hex = id.toUpperCase();
    if (hex.length <= 16) {
      return hex;
    }
    final buf = StringBuffer();
    for (var i = 0; i < hex.length; i += 2) {
      if (i > 0) {
        buf.write(':');
      }
      buf.write(hex.substring(i, i + 2));
    }
    return buf.toString();
  }

  static const fromJson = SyncContactMapper.fromJson;
}
