import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_downloader/core/link_server.dart';

const _token = 'test-token-abcdefghijklmnop';
const _origin = 'chrome-extension://abcdefghijklmnopabcdefghijklmnop';

void main() {
  late LinkServer server;
  late Directory sessions;
  late HttpClient client;
  late int port;

  setUp(() async {
    sessions = Directory.systemTemp.createTempSync('link_server_test');
    // Port 0 asks the OS for a free one, so the suite cannot collide with a
    // running instance of the app or with a parallel test.
    server = LinkServer(port: 0, sessionsDir: () async => sessions);
    await server.start(_token);
    port = server.boundPort!;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.dispose();
    sessions.deleteSync(recursive: true);
  });

  Future<HttpClientResponse> request(
    String method,
    String path, {
    Object? body,
    String? token = _token,
    String? origin = _origin,
    String? host,
  }) async {
    final req = await client.open(method, '127.0.0.1', port, path);
    if (token != null) req.headers.set('x-auth-token', token);
    if (origin != null) req.headers.set('origin', origin);
    if (host != null) req.headers.set('host', host);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    return req.close();
  }

  Future<HttpClientResponse> add(Map<String, Object?> body,
          {String? token = _token, String? origin = _origin}) =>
      request('POST', '/add', body: body, token: token, origin: origin);

  group('authorisation', () {
    test('accepts a correctly signed ping', () async {
      final response = await request('GET', '/ping');

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.transform(utf8.decoder).join());
      expect((body as Map)['app'], 'video_downloader');
    });

    test('rejects a request with no token', () async {
      expect((await request('GET', '/ping', token: null)).statusCode, 401);
    });

    test('rejects a wrong token', () async {
      expect(
        (await request('GET', '/ping', token: 'wrong-token-aaaaaaaaaaaaaa'))
            .statusCode,
        401,
      );
    });

    test('rejects a token that is a prefix of the real one', () async {
      // Guards the length check in the constant-time comparison.
      expect(
        (await request('GET', '/ping', token: _token.substring(0, 8)))
            .statusCode,
        401,
      );
    });

    test('rejects a web page origin even with the right token', () async {
      // A page that somehow learned the key still must not be able to drive
      // the app.
      final response =
          await request('GET', '/ping', origin: 'https://evil.invalid');

      expect(response.statusCode, 403);
    });

    test('rejects a non-loopback Host header, blocking DNS rebinding', () async {
      // An attacker's domain resolving to 127.0.0.1 sends its own name here.
      final response =
          await request('GET', '/ping', host: 'attacker.invalid:$port');

      expect(response.statusCode, 403);
    });

    test('allows a Firefox extension origin', () async {
      final response = await request('GET', '/ping',
          origin: 'moz-extension://11111111-2222-3333-4444-555555555555');

      expect(response.statusCode, 200);
    });

    test('answers a preflight without requiring the token', () async {
      final response = await request('OPTIONS', '/add', token: null);

      expect(response.statusCode, 204);
      expect(response.headers.value('access-control-allow-origin'), _origin);
    });
  });

  group('/add', () {
    test('emits the link and reports success', () async {
      final received = server.links.first;

      final response = await add({
        'url': 'https://example.invalid/watch?v=1',
        'title': 'Example',
        'userAgent': 'Mozilla/5.0 (Test)',
        'referer': 'https://example.invalid/watch?v=1',
      });

      expect(response.statusCode, 200);
      final link = await received.timeout(const Duration(seconds: 5));
      expect(link.url, 'https://example.invalid/watch?v=1');
      expect(link.title, 'Example');
      expect(link.userAgent, 'Mozilla/5.0 (Test)');
      expect(link.referer, 'https://example.invalid/watch?v=1');
      expect(link.cookiesFile, isNull);
    });

    test('writes the cookies to a jar and points the link at it', () async {
      final received = server.links.first;

      await add({
        'url': 'https://videos.example.invalid/watch',
        'cookies': [
          {
            'domain': '.example.invalid',
            'name': 'sid',
            'value': 'abc123',
            'secure': true,
            'expirationDate': 1893456000,
          }
        ],
      });

      final link = await received.timeout(const Duration(seconds: 5));
      expect(link.cookiesFile, isNotNull);

      final jar = File(link.cookiesFile!);
      expect(jar.existsSync(), isTrue);
      expect(jar.readAsStringSync(), contains('sid\tabc123'));
      // Named after the site, so a second send for the same host replaces it.
      expect(p.basename(jar.path), 'videos.example.invalid.txt');
    });

    test('a later send for the same host replaces the earlier jar', () async {
      // Keeping both would leave an expired cookie sitting beside the fresh
      // one, and yt-dlp would send them together.
      Future<void> send(String value) async {
        final received = server.links.first;
        await add({
          'url': 'https://example.invalid/watch',
          'cookies': [
            {'domain': '.example.invalid', 'name': 'sid', 'value': value}
          ],
        });
        await received.timeout(const Duration(seconds: 5));
      }

      await send('first');
      await send('second');

      final jars = sessions.listSync().whereType<File>().toList();
      expect(jars, hasLength(1));
      expect(jars.single.readAsStringSync(), contains('second'));
      expect(jars.single.readAsStringSync(), isNot(contains('first')));
    });

    test('a hostile host name cannot escape the sessions directory', () async {
      final received = server.links.first;

      await add({
        // Parses as a URL whose host contains path separators once decoded.
        'url': 'https://ex%2F..%2F..%2Fevil.invalid/watch',
        'cookies': [
          {'domain': 'ex.invalid', 'name': 'a', 'value': 'b'}
        ],
      });

      final link = await received.timeout(const Duration(seconds: 5));
      if (link.cookiesFile != null) {
        expect(p.dirname(link.cookiesFile!), sessions.path);
      }
    });

    test('rejects a body that is not JSON', () async {
      final req = await client.open('POST', '127.0.0.1', port, '/add');
      req.headers.set('x-auth-token', _token);
      req.headers.set('origin', _origin);
      req.write('this is not json');

      expect((await req.close()).statusCode, 400);
    });

    test('rejects a missing url', () async {
      expect((await add({'title': 'no url here'})).statusCode, 400);
    });

    test('rejects a non-http scheme', () async {
      // file:// would make yt-dlp read from the local disk.
      expect(
        (await add({'url': 'file:///C:/Windows/System32/config/SAM'}))
            .statusCode,
        400,
      );
    });

    test('rejects GET', () async {
      expect((await request('GET', '/add')).statusCode, 405);
    });

    test('an unknown endpoint is a 404, not a crash', () async {
      expect((await request('GET', '/whatever')).statusCode, 404);
    });

    test('malformed cookies are skipped without losing the link', () async {
      final received = server.links.first;

      final response = await add({
        'url': 'https://example.invalid/watch',
        'cookies': [
          {'name': 'no domain'},
          'not an object',
        ],
      });

      expect(response.statusCode, 200);
      final link = await received.timeout(const Duration(seconds: 5));
      // Nothing usable survived, so no jar was written — but the URL still
      // arrived, and the download can still be attempted signed-out.
      expect(link.cookiesFile, isNull);
    });
  });

  group('lifecycle', () {
    test('stop releases the port', () async {
      await server.stop();

      expect(server.isRunning, isFalse);
      await expectLater(
        request('GET', '/ping'),
        throwsA(isA<SocketException>()),
      );
    });

    test('a second start on a taken port fails with a clear message', () async {
      final other = LinkServer(port: port, sessionsDir: () async => sessions);

      await expectLater(
        other.start(_token),
        throwsA(isA<LinkServerException>()),
      );
      await other.dispose();
    });
  });

  group('generateToken', () {
    test('is unguessable and URL-safe', () {
      final tokens = {for (var i = 0; i < 50; i++) LinkServer.generateToken()};

      expect(tokens, hasLength(50));
      for (final token in tokens) {
        expect(token.length, greaterThanOrEqualTo(40));
        expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      }
    });
  });
}
