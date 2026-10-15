import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/model/persistence/sync_share.dart';
import 'package:localsend_app/provider/sync/plan_response.dart';

/// Lightweight HTTP client for the directory-sync protocol. Talks to a
/// *sender* device that is running the v2 server with one or more sync
/// shares enabled.
///
/// The protocol is unauthenticated in v1: it relies on the LAN being
/// trusted. There is no TLS client certificate and no PIN; the sender's
/// `prepare-upload` / `register` flow does not cover these endpoints. If
/// the design ever grows auth, fold it into [request] rather than
/// scattering headers through each call.
class SyncHttpClient {
  final String _host;
  final int _port;
  final Duration _timeout;
  final bool _useTls;

  SyncHttpClient({
    required String host,
    required int port,
    bool useTls = false,
    Duration timeout = const Duration(seconds: 10),
  })  : _host = host,
        _port = port,
        _useTls = useTls,
        _timeout = timeout;

  String get _baseUrl => '${_useTls ? 'https' : 'http'}://$_host:$_port';

  /// The base URL (`http://host:port` or `https://...`). Exposed so
  /// the sync session can hit a `POST` endpoint without re-parsing the
  /// host/port from the [Device].
  String get baseUrl => _baseUrl;

  /// The connection + response timeout this client uses. Exposed so
  /// callers composing their own requests (the plan POST) can apply
  /// the same budget.
  Duration get timeout => _timeout;

  /// `GET /api/localsend/sync/` -> list of available shares.
  Future<List<RemoteSyncShare>> listShares() async {
    final body = await request('GET', '/api/localsend/sync/');
    final decoded = jsonDecode(utf8.decode(body)) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(RemoteSyncShare.fromJson)
        .toList(growable: false);
  }

  /// `GET /api/localsend/sync/{id}/manifest` -> manifest JSON. Throws
  /// [SyncHttpException] when the share is unknown or the response body
  /// cannot be parsed.
  Future<RemoteSyncManifest> getManifest(String shareId) async {
    final body = await request('GET', '/api/localsend/sync/$shareId/manifest');
    return RemoteSyncManifest.fromJson(
      jsonDecode(utf8.decode(body)) as Map<String, dynamic>,
    );
  }

  /// `GET /api/localsend/sync/{id}/tree?path=...` -> entries directly
  /// under the given path. Pass the empty string (or `/`) to query the
  /// root.
  Future<List<RemoteSyncTreeEntry>> getTree(String shareId, {String path = ''}) async {
    final query = path.isEmpty || path == '/' ? '' : '?path=${Uri.encodeQueryComponent(path)}';
    final body = await request('GET', '/api/localsend/sync/$shareId/tree$query');
    final decoded = jsonDecode(utf8.decode(body)) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(RemoteSyncTreeEntry.fromJson)
        .toList(growable: false);
  }

  /// `GET /api/localsend/sync/{id}/file?path=...` -> file bytes. The
  /// receiver streams the response into a local file; this method returns
  /// the raw bytes because most calls are small and want to keep the
  /// path simple. Big files should use a streaming variant once we know
  /// the typical sizes.
  Future<List<int>> getFile(String shareId, String path) async {
    final body = await request('GET', '/api/localsend/sync/$shareId/file', query: {'path': path});
    return body;
  }

  /// `POST /api/localsend/sync/{id}/plan` with the receiver's local
  /// manifest and `previous_paths`, parsed as a [RemoteSyncPlan]. See
  /// `plan_response.dart` for the request shape.
  Future<RemoteSyncPlan> postPlan(
    String shareId, {
    required List<RemoteSyncEntry> local,
    required List<String> previousPaths,
  }) async {
    final body = utf8.encode(jsonEncode(planRequestBody(local: local, previousPaths: previousPaths)));
    final uri = Uri.parse('$_baseUrl/api/localsend/sync/$shareId/plan');
    final http = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await http.openUrl('POST', uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(body);
      final res = await req.close().timeout(_timeout);
      final responseBody = await _collectBytes(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw SyncHttpException(
          method: 'POST',
          path: '/api/localsend/sync/$shareId/plan',
          statusCode: res.statusCode,
          body: utf8.decode(responseBody, allowMalformed: true),
        );
      }
      final json = jsonDecode(utf8.decode(responseBody)) as Map<String, dynamic>;
      return RemoteSyncPlan.fromJson(json);
    } on SocketException catch (e) {
      throw SyncHttpException(
        method: 'POST',
        path: '/api/localsend/sync/$shareId/plan',
        networkError: e.message,
      );
    } on TimeoutException catch (e) {
      throw SyncHttpException(
        method: 'POST',
        path: '/api/localsend/sync/$shareId/plan',
        networkError: 'timeout: ${e.message}',
      );
    } finally {
      http.close(force: true);
    }
  }

  /// Low-level request helper. Decodes the response body as a list of
  /// bytes. Throws [SyncHttpException] on non-2xx responses so callers
  /// don't have to repeat the status-code plumbing.
  Future<List<int>> request(String method, String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(_timeout);
      final body = await _collectBytes(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw SyncHttpException(
          method: method,
          path: path,
          statusCode: res.statusCode,
          body: utf8.decode(body, allowMalformed: true),
        );
      }
      return body;
    } on SocketException catch (e) {
      throw SyncHttpException(method: method, path: path, networkError: e.message);
    } on TimeoutException catch (e) {
      throw SyncHttpException(method: method, path: path, networkError: 'timeout: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<int>> _collectBytes(HttpClientResponse res) async {
    final builder = <int>[];
    await for (final chunk in res) {
      builder.addAll(chunk);
    }
    return builder;
  }
}

/// Errors from [SyncHttpClient]. Distinguishes "the server said no" from
/// "we could not talk to the server at all" because the receiver UI
/// reacts differently: a 404 means the sender has no shares (probe
/// elsewhere), a socket error means the sender has gone away.
class SyncHttpException implements Exception {
  final String method;
  final String path;
  final int? statusCode;
  final String? body;
  final String? networkError;

  const SyncHttpException({
    required this.method,
    required this.path,
    this.statusCode,
    this.body,
    this.networkError,
  });

  bool get isNetwork => networkError != null;

  @override
  String toString() {
    if (isNetwork) {
      return 'SyncHttpException($method $path: network $networkError)';
    }
    return 'SyncHttpException($method $path: $statusCode $body)';
  }
}

/// Sender-side share metadata as returned by `GET /api/localsend/sync/`.
class RemoteSyncShare {
  final String id;
  final String name;

  const RemoteSyncShare({required this.id, required this.name});

  factory RemoteSyncShare.fromJson(Map<String, dynamic> j) =>
      RemoteSyncShare(id: j['id'] as String, name: j['name'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// A manifest entry, as returned by `GET /api/localsend/sync/{id}/manifest`.
/// This is the sender's view; the receiver only needs a subset of the
/// fields, but keeping the full shape makes it easy to plug the same
/// data into the diff engine later.
class RemoteSyncManifest {
  final int version;
  final String generatedAt;
  final List<String> excludes;
  final List<RemoteSyncEntry> entries;

  const RemoteSyncManifest({
    required this.version,
    required this.generatedAt,
    required this.excludes,
    required this.entries,
  });

  factory RemoteSyncManifest.fromJson(Map<String, dynamic> j) => RemoteSyncManifest(
        version: (j['version'] as num).toInt(),
        generatedAt: j['generated_at'] as String,
        excludes: (j['excludes'] as List<dynamic>).cast<String>(),
        entries: (j['entries'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RemoteSyncEntry.fromJson)
            .toList(growable: false),
      );
}

/// One entry inside a [RemoteSyncManifest]. Mirrors the server-side
/// `sync::manifest::Entry` shape. The `mode` field carries the Unix
/// permission bits; the receiver only uses it to distinguish regular
/// files from directories and symlinks via [isRegularFile].
class RemoteSyncEntry {
  final String path;
  final int size;
  final int mtimeUnix;
  final String sha256;
  final int mode;

  const RemoteSyncEntry({
    required this.path,
    required this.size,
    required this.mtimeUnix,
    required this.sha256,
    required this.mode,
  });

  /// True when the entry is a regular file (the only kind transferred in
  /// v1). Matches `libc::S_ISREG` semantically: bit 0o170000 cleared
  /// plus bit 0o100000 set, but here we rely on `mode` being non-zero
  /// for regular files and 0 for non-regular entries. The server's
  /// `manifest::compute` always sets `mode` for files and 0 otherwise.
  /// Dart has no octal literals, so we use the equivalent hex form:
  /// 0o170000 = 0xF000, 0o100000 = 0x8000.
  bool get isRegularFile => (mode & 0xF000) == 0x8000;

  factory RemoteSyncEntry.fromJson(Map<String, dynamic> j) => RemoteSyncEntry(
        path: j['path'] as String,
        size: (j['size'] as num).toInt(),
        mtimeUnix: (j['mtime_unix'] as num).toInt(),
        sha256: j['sha256'] as String,
        mode: (j['mode'] as num).toInt(),
      );
}

/// A single tree node as returned by `GET /api/localsend/sync/{id}/tree`.
class RemoteSyncTreeEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;

  const RemoteSyncTreeEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
  });

  factory RemoteSyncTreeEntry.fromJson(Map<String, dynamic> j) => RemoteSyncTreeEntry(
        name: j['name'] as String,
        path: j['path'] as String,
        isDir: j['is_dir'] as bool,
        size: (j['size'] as num).toInt(),
      );
}

/// Marker: a local [SyncShare] and a remote [RemoteSyncShare] belong to
/// the *same* logical share when these match. Kept here (rather than in
/// the provider) because the matcher is pure data and a future test
/// will want to import it.
bool shareIdsMatch(SyncShare local, RemoteSyncShare remote) => local.id == remote.id;
