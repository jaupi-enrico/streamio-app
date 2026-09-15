import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for the backend origin the app talks to.
///
/// There is no compile-time base URL: the server is self-hosted and its
/// address changes per deployment. The user types it in on first launch (see
/// features/setup/server_setup_screen.dart) and it can be changed later.
class ServerConfig {
  static const _baseUrlKey = 'server_base_url';
  static const _recentKey = 'recent_server_urls';
  static const _maxRecent = 5;

  /// Accepts what a person actually types ("myhost.example.com",
  /// "http://192.168.1.10:3003/", "https://example.com/streamio") and
  /// returns a canonical base with no trailing slash. Returns null if there's
  /// nothing usable in it.
  ///
  /// A **path prefix is preserved**: an install behind a reverse proxy is
  /// commonly mounted under one (`https://example.com/streamio`), and
  /// every URL the app builds appends to this string, so dropping the prefix
  /// would point every request at the wrong place.
  static String? normalize(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    // Trailing slashes go so '$base/api/...' concatenation is safe.
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');

    // Built by hand rather than with Uri.replace(query: '', fragment: ''),
    // which leaves a bare '?' on the end — that would then be glued to the
    // front of every path appended to this base.
    final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    return '${uri.scheme}://$authority$path';
  }

  /// [base] plus each shorter path prefix, longest first.
  ///
  /// Someone copying the address out of their browser mid-browse pastes a
  /// page URL (`.../streamio/watch`), not the server root. Probing these in
  /// order finds the real base instead of just failing.
  static List<String> candidates(String base) {
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) return [base];

    final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    final origin = '${uri.scheme}://$authority';

    final segments =
        uri.path.split('/').where((segment) => segment.isNotEmpty).toList();

    final result = <String>[];
    for (var length = segments.length; length > 0; length--) {
      result.add('$origin/${segments.take(length).join('/')}');
    }
    result.add(origin);
    return result;
  }

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey);
  }

  static Future<void> write(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, baseUrl);

    final recent = prefs.getStringList(_recentKey) ?? <String>[];
    recent
      ..remove(baseUrl)
      ..insert(0, baseUrl);
    await prefs.setStringList(
        _recentKey, recent.take(_maxRecent).toList(growable: false));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baseUrlKey);
  }

  static Future<List<String>> recent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? const <String>[];
  }
}

/// Outcome of probing a candidate base URL, so the setup screen can tell
/// "wrong address" apart from "right address, server still waking up".
enum ServerProbeResult {
  ok,

  /// Reachable, but not answering as Streamio. A proxy in front of the
  /// install may serve a static waiting page while the host behind it is
  /// still coming up, so a plain 200 of HTML is a real and expected state
  /// here — not a typo'd host.
  reachableNotReady,

  unreachable,
}

class ServerProbe {
  const ServerProbe(this.result, {this.detail, this.resolvedBase});

  final ServerProbeResult result;
  final String? detail;

  /// The base that actually answered — not necessarily the one passed in, if
  /// a path had to be trimmed off (see [probeServerCandidates]).
  final String? resolvedBase;

  bool get isOk => result == ServerProbeResult.ok;

  ServerProbe withBase(String base) =>
      ServerProbe(result, detail: detail, resolvedBase: base);
}

/// Probes [base], then each shorter path prefix, stopping at the first one
/// that answers as Streamio.
///
/// This is what the setup screen calls. Typing the exact base is the common
/// case, but pasting a page URL out of a browser is common too, and an
/// install mounted at `https://host/streamio` makes the difference between
/// the two invisible from the outside — only a probe can tell them apart.
Future<ServerProbe> probeServerCandidates(String base, {Dio? client}) async {
  final candidates = ServerConfig.candidates(base);
  ServerProbe? firstFailure;

  for (final candidate in candidates) {
    final probe = await probeServer(candidate, client: client);
    if (probe.isOk) return probe.withBase(candidate);
    firstFailure ??= probe.withBase(candidate);

    // An unreachable host won't become reachable by trimming its path.
    if (probe.result == ServerProbeResult.unreachable) break;
  }

  return firstFailure ?? const ServerProbe(ServerProbeResult.unreachable);
}

/// Turns the URL that actually served `/health` back into a base by dropping
/// that trailing segment. Returns null if it doesn't end in `/health`, in
/// which case the caller keeps what it had.
String? _baseFromHealthUrl(Uri realUri) {
  final segments = [...realUri.pathSegments]..removeWhere((s) => s.isEmpty);
  if (segments.isEmpty || segments.last != 'health') return null;
  segments.removeLast();

  final authority =
      realUri.hasPort ? '${realUri.host}:${realUri.port}' : realUri.host;
  final path = segments.isEmpty ? '' : '/${segments.join('/')}';
  return '${realUri.scheme}://$authority$path';
}

/// `GET {base}/health` — health.router.ts answers with JSON. A 2xx that
/// isn't JSON means something else is on that origin (or the tunnel is
/// still showing its waiting page).
Future<ServerProbe> probeServer(String baseUrl, {Dio? client}) async {
  final dio = client ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 500,
        responseType: ResponseType.plain,
        followRedirects: true,
      ));

  try {
    final response = await dio.get<String>('$baseUrl/health');
    final status = response.statusCode ?? 0;
    final body = (response.data ?? '').trimLeft();

    if (status >= 200 && status < 300 && body.startsWith('{')) {
      // Adopt wherever the redirects landed. The address typed at setup may
      // answer with a 302 to the one actually serving the install, and
      // storing the address that actually served us means the app stops
      // paying that hop on every subsequent request.
      return ServerProbe(
        ServerProbeResult.ok,
        resolvedBase: _baseFromHealthUrl(response.realUri) ?? baseUrl,
      );
    }
    if (status >= 200 && status < 400) {
      return const ServerProbe(
        ServerProbeResult.reachableNotReady,
        detail: 'Reached the address, but it did not answer as Streamio. '
            'If this is the tunnel, it may still be starting up.',
      );
    }
    return ServerProbe(
      ServerProbeResult.reachableNotReady,
      detail: 'Server answered HTTP $status.',
    );
  } on DioException catch (err) {
    return ServerProbe(
      ServerProbeResult.unreachable,
      detail: switch (err.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout =>
          'Timed out connecting to the server.',
        DioExceptionType.badCertificate =>
          'The server\'s TLS certificate was rejected.',
        _ => 'Could not reach the server.',
      },
    );
  } catch (_) {
    return const ServerProbe(
      ServerProbeResult.unreachable,
      detail: 'Could not reach the server.',
    );
  }
}
