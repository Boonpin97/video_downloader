import 'dart:convert';
import 'dart:io';

/// Handling for Netscape-format cookie jars — the `cookies.txt` files that
/// browser export extensions produce and that yt-dlp reads via `--cookies`.
///
/// This exists because `--cookies-from-browser` stopped being dependable:
/// Chrome 127 introduced App-Bound Encryption, which makes the cookie database
/// unreadable to any process other than Chrome itself. An exported jar is the
/// only route left to a signed-in or captcha-cleared session on those browsers.
class CookieJar {
  /// Human-readable reason the file at [path] is unusable, or `null` if it
  /// looks like a jar yt-dlp will accept.
  ///
  /// Checked at pick time rather than at download time so the user finds out
  /// while they are still looking at the file chooser, instead of via a yt-dlp
  /// stderr dump twenty minutes later.
  static String? validate(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return 'That file no longer exists.';
    }

    final String contents;
    try {
      contents = file.readAsStringSync();
    } on FileSystemException catch (e) {
      return 'That file could not be read — ${e.osError?.message ?? e.message}.';
    }

    if (contents.trim().isEmpty) {
      return 'That file is empty. Export the cookies again with the site open '
          'and signed in.';
    }
    if (!_hasCookieLine(contents)) {
      return 'That does not look like a cookies.txt file. Export one in '
          'Netscape format from your browser.';
    }
    return null;
  }

  /// A data line is tab-separated with seven fields: domain, include
  /// subdomains, path, secure, expiry, name, value. Comment lines start with
  /// `#`, except `#HttpOnly_` which prefixes a real domain.
  static bool _hasCookieLine(String contents) {
    for (final line in const LineSplitter().convert(contents)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#') && !trimmed.startsWith('#HttpOnly_')) {
        continue;
      }
      if (trimmed.split('\t').length >= 7) return true;
    }
    return false;
  }

  /// Renders cookies collected by the browser extension into the same Netscape
  /// format an export tool would have produced.
  ///
  /// Doing the formatting here rather than in the extension keeps the one part
  /// that yt-dlp is fussy about inside testable Dart, and leaves the extension
  /// as a thin `chrome.cookies.getAll()` relay.
  static String toNetscape(Iterable<BrowserCookie> cookies) {
    final buffer = StringBuffer()
      ..writeln('# Netscape HTTP Cookie File')
      ..writeln('# Written by Video Downloader. Do not edit.')
      ..writeln();

    for (final cookie in cookies) {
      // A leading dot is what marks a domain cookie, and the second column has
      // to agree with it — yt-dlp reads both, and disagreement makes cookies
      // silently fail to match the request.
      final domain = cookie.hostOnly
          ? _stripDot(cookie.domain)
          : '.${_stripDot(cookie.domain)}';
      final line = [
        cookie.httpOnly ? '#HttpOnly_$domain' : domain,
        cookie.hostOnly ? 'FALSE' : 'TRUE',
        cookie.path.isEmpty ? '/' : cookie.path,
        cookie.secure ? 'TRUE' : 'FALSE',
        // 0 is the convention for a session cookie, which is exactly what a
        // freshly solved captcha often issues.
        (cookie.expiresAt ?? 0).toString(),
        cookie.name,
        cookie.value,
      ].join('\t');
      buffer.writeln(line);
    }
    return buffer.toString();
  }

  static String _stripDot(String domain) =>
      domain.startsWith('.') ? domain.substring(1) : domain;
}

/// One cookie as the browser reported it.
class BrowserCookie {
  const BrowserCookie({
    required this.domain,
    required this.name,
    required this.value,
    this.path = '/',
    this.secure = false,
    this.httpOnly = false,
    this.hostOnly = false,
    this.expiresAt,
  });

  final String domain;
  final String name;
  final String value;
  final String path;
  final bool secure;
  final bool httpOnly;
  final bool hostOnly;

  /// Unix seconds. `null` for a session cookie that dies with the browser.
  final int? expiresAt;

  /// Skips entries that are missing the parts a jar line cannot do without,
  /// so one malformed cookie cannot poison the whole jar.
  static BrowserCookie? fromJson(Object? value) {
    if (value is! Map) return null;
    final domain = value['domain'];
    final name = value['name'];
    if (domain is! String || domain.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;

    final expires = value['expirationDate'];
    return BrowserCookie(
      domain: domain,
      name: name,
      value: value['value'] is String ? value['value'] as String : '',
      path: value['path'] is String && (value['path'] as String).isNotEmpty
          ? value['path'] as String
          : '/',
      secure: value['secure'] == true,
      httpOnly: value['httpOnly'] == true,
      hostOnly: value['hostOnly'] == true,
      // Chrome reports this as a float; yt-dlp wants whole seconds.
      expiresAt: expires is num ? expires.floor() : null,
    );
  }
}
