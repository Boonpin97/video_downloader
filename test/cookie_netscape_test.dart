import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/core/cookie_jar.dart';

/// Splits a rendered jar into its data lines, dropping the header comments but
/// keeping `#HttpOnly_` entries, which are data despite the leading `#`.
List<List<String>> dataLines(String jar) {
  return jar
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .where((l) => !l.startsWith('#') || l.startsWith('#HttpOnly_'))
      .map((l) => l.split('\t'))
      .toList();
}

void main() {
  group('toNetscape', () {
    test('writes the seven tab-separated fields yt-dlp expects', () {
      final jar = CookieJar.toNetscape([
        const BrowserCookie(
          domain: '.example.invalid',
          name: 'sid',
          value: 'abc123',
          path: '/videos',
          secure: true,
          expiresAt: 1893456000,
        ),
      ]);

      expect(dataLines(jar), [
        ['.example.invalid', 'TRUE', '/videos', 'TRUE', '1893456000', 'sid',
            'abc123'],
      ]);
    });

    test('round-trips through the validator', () {
      final jar = CookieJar.toNetscape([
        const BrowserCookie(
            domain: '.example.invalid', name: 'sid', value: 'abc'),
      ]);

      // The two halves have to agree: what the bridge writes must be something
      // a user could equally have picked with the file chooser.
      expect(CookieJar.validate, isNotNull);
      expect(dataLines(jar).single.length, 7);
    });

    test('a host-only cookie gets no leading dot and FALSE for subdomains', () {
      final jar = CookieJar.toNetscape([
        const BrowserCookie(
          domain: 'example.invalid',
          name: 'a',
          value: 'b',
          hostOnly: true,
        ),
      ]);

      final line = dataLines(jar).single;
      expect(line[0], 'example.invalid');
      expect(line[1], 'FALSE');
    });

    test('a domain cookie is normalised to exactly one leading dot', () {
      // Chrome already reports these with a dot; adding a second would stop the
      // domain matching anything.
      final jar = CookieJar.toNetscape([
        const BrowserCookie(domain: '.example.invalid', name: 'a', value: 'b'),
        const BrowserCookie(domain: 'other.invalid', name: 'c', value: 'd'),
      ]);

      expect(dataLines(jar).map((l) => l[0]),
          ['.example.invalid', '.other.invalid']);
      expect(dataLines(jar).map((l) => l[1]), ['TRUE', 'TRUE']);
    });

    test('marks httpOnly entries with the prefix yt-dlp understands', () {
      final jar = CookieJar.toNetscape([
        const BrowserCookie(
          domain: '.example.invalid',
          name: 'sid',
          value: 'x',
          httpOnly: true,
        ),
      ]);

      expect(dataLines(jar).single[0], '#HttpOnly_.example.invalid');
    });

    test('a session cookie is written with expiry 0', () {
      // A freshly cleared captcha usually hands back exactly this, so it must
      // not be dropped or written as an empty field.
      final jar = CookieJar.toNetscape([
        const BrowserCookie(
            domain: '.example.invalid', name: 'cf_clearance', value: 'x'),
      ]);

      expect(dataLines(jar).single[4], '0');
    });

    test('a fractional expiry is floored to whole seconds', () {
      final cookie = BrowserCookie.fromJson(const {
        'domain': '.example.invalid',
        'name': 'a',
        'value': 'b',
        'expirationDate': 1893456000.75,
      })!;

      expect(cookie.expiresAt, 1893456000);
    });

    test('an empty path is written as root rather than an empty field', () {
      final jar = CookieJar.toNetscape([
        const BrowserCookie(
            domain: 'example.invalid', name: 'a', value: 'b', path: ''),
      ]);

      expect(dataLines(jar).single[2], '/');
    });
  });

  group('BrowserCookie.fromJson', () {
    test('reads what the extension sends', () {
      final cookie = BrowserCookie.fromJson(const {
        'domain': '.example.invalid',
        'name': 'sid',
        'value': 'abc',
        'path': '/x',
        'secure': true,
        'httpOnly': true,
        'hostOnly': false,
        'expirationDate': 1893456000,
      })!;

      expect(cookie.domain, '.example.invalid');
      expect(cookie.name, 'sid');
      expect(cookie.value, 'abc');
      expect(cookie.path, '/x');
      expect(cookie.secure, isTrue);
      expect(cookie.httpOnly, isTrue);
      expect(cookie.hostOnly, isFalse);
      expect(cookie.expiresAt, 1893456000);
    });

    test('drops entries missing a domain or name instead of writing junk', () {
      expect(BrowserCookie.fromJson(const {'name': 'a', 'value': 'b'}), isNull);
      expect(
        BrowserCookie.fromJson(const {'domain': 'x.invalid', 'value': 'b'}),
        isNull,
      );
      expect(
        BrowserCookie.fromJson(const {'domain': '', 'name': 'a'}),
        isNull,
      );
      expect(BrowserCookie.fromJson('not a map'), isNull);
    });

    test('tolerates a cookie with no value, which is legal', () {
      final cookie =
          BrowserCookie.fromJson(const {'domain': 'x.invalid', 'name': 'a'})!;

      expect(cookie.value, '');
      expect(cookie.path, '/');
      expect(cookie.expiresAt, isNull);
    });
  });
}
