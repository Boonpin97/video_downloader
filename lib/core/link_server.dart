import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'cookie_jar.dart';
import 'paths.dart';

/// A link handed over by the browser extension, with the session that was
/// authenticated in the browser already written to disk.
class IncomingLink {
  const IncomingLink({
    required this.url,
    this.title,
    this.cookiesFile,
    this.userAgent,
    this.referer,
  });

  final String url;
  final String? title;

  /// Path to the jar written from the cookies the extension sent, or `null` if
  /// it sent none.
  final String? cookiesFile;

  final String? userAgent;
  final String? referer;
}

/// Receives "download this page" requests from the browser extension.
///
/// A loopback HTTP server rather than a native messaging host: native messaging
/// would need a registry-registered manifest pointing at a stdio relay
/// executable, which is a lot of installer machinery for a link and a cookie
/// jar. The cost is that a loopback port is reachable by anything else on the
/// machine, which is what the checks in [_authorise] are defending.
class LinkServer {
  LinkServer({this.port = defaultPort, Future<Directory> Function()? sessionsDir})
      : _sessionsDir = sessionsDir ?? _defaultSessionsDir;

  /// Arbitrary high port, matching the extension's default.
  static const defaultPort = 47823;

  /// Requests above this are rejected unread. A jar for one site is a few KB;
  /// anything near the cap is not a cookie jar.
  static const _maxBodyBytes = 1024 * 1024;

  final int port;

  /// Where cookie jars are written. Injectable so tests can exercise the write
  /// without the platform channel `path_provider` needs.
  final Future<Directory> Function() _sessionsDir;

  HttpServer? _server;
  String? _token;

  final _links = StreamController<IncomingLink>.broadcast();

  /// Links sent from the browser, for the UI to pick up and queue.
  Stream<IncomingLink> get links => _links.stream;

  bool get isRunning => _server != null;

  /// The port actually listening, which differs from [port] only when 0 was
  /// passed to let the OS choose one. `null` while stopped.
  int? get boundPort => _server?.port;

  /// Starts listening on the loopback interface only, so the port is not
  /// exposed to the local network.
  ///
  /// Throws [LinkServerException] if the port is already taken, which is the
  /// one failure the user can act on.
  Future<void> start(String token) async {
    if (_server != null) return;
    _token = token;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      server.listen(_handle, onError: (_) {
        // A malformed request should not take the listener down with it.
      });
    } on SocketException catch (e) {
      throw LinkServerException(
        'Could not listen on port $port — ${e.osError?.message ?? e.message}. '
        'Another program may be using it.',
      );
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _links.close();
  }

  /// A URL-safe secret the extension must present on every request.
  static String generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final origin = request.headers.value('origin');
      if (origin != null && _isExtensionOrigin(origin)) {
        response.headers
          ..set('access-control-allow-origin', origin)
          ..set('access-control-allow-headers', 'content-type, x-auth-token')
          ..set('access-control-allow-methods', 'POST, OPTIONS');
      }
      // The extension's POST is preflighted because it carries a custom header.
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        return;
      }

      final rejection = _authorise(request);
      if (rejection != null) {
        response.statusCode = rejection;
        await _writeJson(response, {'error': 'rejected'});
        return;
      }

      switch (request.uri.path) {
        case '/ping':
          await _writeJson(response, {'app': 'video_downloader', 'version': 1});
        case '/add':
          await _handleAdd(request, response);
        default:
          response.statusCode = HttpStatus.notFound;
          await _writeJson(response, {'error': 'unknown endpoint'});
      }
    } catch (_) {
      // Never leak an internal error's text back to the caller.
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // Headers already sent; nothing left to say.
      }
    } finally {
      await response.close();
    }
  }

  /// Returns the status to reject with, or `null` to allow.
  ///
  /// Three separate concerns: the shared secret proves it is *our* extension;
  /// the Origin check keeps ordinary web pages out even if they learn the
  /// token; the Host check defeats DNS rebinding, where an attacker's domain
  /// resolves to 127.0.0.1 so their page's requests look local.
  int? _authorise(HttpRequest request) {
    final host = request.headers.value('host');
    if (host == null || !_isLoopbackHost(host)) {
      return HttpStatus.forbidden;
    }

    final origin = request.headers.value('origin');
    if (origin != null && !_isExtensionOrigin(origin)) {
      return HttpStatus.forbidden;
    }

    final presented = request.headers.value('x-auth-token');
    final expected = _token;
    if (expected == null || presented == null) {
      return HttpStatus.unauthorized;
    }
    if (!_secureEquals(presented, expected)) {
      return HttpStatus.unauthorized;
    }
    return null;
  }

  Future<void> _handleAdd(HttpRequest request, HttpResponse response) async {
    if (request.method != 'POST') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await _writeJson(response, {'error': 'POST only'});
      return;
    }
    if (request.contentLength > _maxBodyBytes) {
      response.statusCode = HttpStatus.requestEntityTooLarge;
      await _writeJson(response, {'error': 'body too large'});
      return;
    }

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(await _readBody(request)) as Map<String, dynamic>;
    } catch (_) {
      response.statusCode = HttpStatus.badRequest;
      await _writeJson(response, {'error': 'expected a JSON object'});
      return;
    }

    final url = payload['url'];
    if (url is! String || !_isHttpUrl(url)) {
      response.statusCode = HttpStatus.badRequest;
      await _writeJson(response, {'error': 'missing or non-http url'});
      return;
    }

    String? jarPath;
    final rawCookies = payload['cookies'];
    if (rawCookies is List && rawCookies.isNotEmpty) {
      final cookies = rawCookies
          .map(BrowserCookie.fromJson)
          .whereType<BrowserCookie>()
          .toList();
      if (cookies.isNotEmpty) {
        jarPath = await _writeJar(Uri.parse(url).host, cookies);
      }
    }

    _links.add(IncomingLink(
      url: url,
      title: payload['title'] is String ? payload['title'] as String : null,
      cookiesFile: jarPath,
      userAgent:
          payload['userAgent'] is String ? payload['userAgent'] as String : null,
      referer: payload['referer'] is String ? payload['referer'] as String : null,
    ));

    await _writeJson(response, {'ok': true});
  }

  /// One jar per site, overwritten on each send so the newest session wins.
  ///
  /// These are credentials, so they live in the app's own support directory
  /// rather than anywhere the user might share, and the file is replaced rather
  /// than appended to — a stale expired cookie sitting alongside a fresh one
  /// makes yt-dlp send both and can invalidate the session.
  Future<String?> _writeJar(String host, List<BrowserCookie> cookies) async {
    try {
      final dir = await _sessionsDir();
      if (!dir.existsSync()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${_safeName(host)}.txt'));
      await file.writeAsString(CookieJar.toNetscape(cookies), flush: true);
      return file.path;
    } on FileSystemException {
      // Losing the jar costs the session, not the download attempt.
      return null;
    }
  }

  static Future<Directory> _defaultSessionsDir() async =>
      Directory(p.join((await AppPaths.supportDir()).path, 'sessions'));

  /// Keeps a hostile `host` from escaping the sessions directory.
  static String _safeName(String host) {
    final cleaned = host.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'site' : cleaned;
  }

  Future<String> _readBody(HttpRequest request) async {
    final chunks = <int>[];
    await for (final chunk in request) {
      chunks.addAll(chunk);
      if (chunks.length > _maxBodyBytes) {
        throw const FormatException('body too large');
      }
    }
    return utf8.decode(chunks, allowMalformed: true);
  }

  Future<void> _writeJson(HttpResponse response, Map<String, Object?> body) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }

  static bool _isExtensionOrigin(String origin) =>
      origin.startsWith('chrome-extension://') ||
      origin.startsWith('moz-extension://');

  static bool _isLoopbackHost(String host) {
    final name = host.split(':').first.toLowerCase();
    return name == '127.0.0.1' || name == 'localhost' || name == '[::1]';
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Compares without an early exit, so response timing does not reveal how
  /// much of a guessed token was correct.
  static bool _secureEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class LinkServerException implements Exception {
  const LinkServerException(this.message);

  final String message;

  @override
  String toString() => message;
}
