import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_downloader/core/cookie_jar.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cookie_jar_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, String contents) {
    final path = p.join(dir.path, name);
    File(path).writeAsStringSync(contents);
    return path;
  }

  test('accepts a jar exported by a browser extension', () {
    final path = write(
      'cookies.txt',
      '# Netscape HTTP Cookie File\n'
      '# This is a generated file! Do not edit.\n\n'
      '.example.invalid\tTRUE\t/\tTRUE\t1893456000\tsession\tabc123\n',
    );

    expect(CookieJar.validate(path), isNull);
  });

  test('accepts httpOnly entries, which carry the real session token', () {
    final path = write(
      'cookies.txt',
      '#HttpOnly_.example.invalid\tTRUE\t/\tTRUE\t1893456000\tsid\txyz\n',
    );

    expect(CookieJar.validate(path), isNull);
  });

  test('rejects a jar with only comments — an export that captured nothing',
      () {
    final path = write('cookies.txt', '# Netscape HTTP Cookie File\n');

    expect(CookieJar.validate(path), contains('does not look like'));
  });

  test('rejects a space-separated near-miss', () {
    // The format is tab-separated; a file mangled by copy-paste through a text
    // editor loses the tabs and yt-dlp would reject it with a parse error.
    final path = write(
      'cookies.txt',
      '.example.invalid TRUE / TRUE 1893456000 session abc123\n',
    );

    expect(CookieJar.validate(path), isNotNull);
  });

  test('reports an empty file distinctly from a malformed one', () {
    expect(CookieJar.validate(write('cookies.txt', '   \n')),
        contains('is empty'));
  });

  test('reports a missing file', () {
    expect(
      CookieJar.validate(p.join(dir.path, 'absent.txt')),
      contains('no longer exists'),
    );
  });
}
