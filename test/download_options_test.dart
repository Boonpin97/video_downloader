import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/models/download_options.dart';

void main() {
  group('sharedArgs', () {
    test('is empty when nothing is configured', () {
      expect(const DownloadOptions().sharedArgs, isEmpty);
    });

    test('passes a cookie jar as --cookies', () {
      expect(
        const DownloadOptions(cookiesFile: r'C:\jars\cookies.txt').sharedArgs,
        ['--cookies', r'C:\jars\cookies.txt'],
      );
    });

    test('a cookie file wins over the browser setting', () {
      // Both set would leave it ambiguous which session authenticated the
      // request, so the explicit file is the one that counts.
      final args = const DownloadOptions(
        cookiesFromBrowser: 'chrome',
        cookiesFile: r'C:\jars\cookies.txt',
      ).sharedArgs;

      expect(args, contains('--cookies'));
      expect(args, isNot(contains('--cookies-from-browser')));
    });

    test('falls back to the browser when no file is set', () {
      expect(
        const DownloadOptions(cookiesFromBrowser: 'firefox').sharedArgs,
        ['--cookies-from-browser', 'firefox'],
      );
    });

    test('blank strings are treated as unset, not as empty flag values', () {
      // An empty text field must not produce `--user-agent ""`, which yt-dlp
      // would send as a literal empty header.
      final args = const DownloadOptions(
        cookiesFile: '',
        cookiesFromBrowser: '   ',
        userAgent: '',
        referer: '  ',
      ).sharedArgs;

      expect(args, isEmpty);
    });

    test('carries the user agent and referer alongside the cookies', () {
      final args = const DownloadOptions(
        cookiesFile: r'C:\jars\cookies.txt',
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        referer: 'https://example.invalid/watch',
      ).sharedArgs;

      expect(
        args,
        containsAllInOrder(
            ['--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)']),
      );
      expect(
        args,
        containsAllInOrder(['--referer', 'https://example.invalid/watch']),
      );
    });
  });

  group('serialisation', () {
    test('round-trips the site-access fields', () {
      const original = DownloadOptions(
        cookiesFile: r'C:\jars\cookies.txt',
        userAgent: 'Mozilla/5.0',
        referer: 'https://example.invalid/',
      );

      final decoded = jsonDecode(jsonEncode(original.toJson()));
      final restored =
          DownloadOptions.fromJson(Map<String, dynamic>.from(decoded as Map));

      expect(restored.cookiesFile, original.cookiesFile);
      expect(restored.userAgent, original.userAgent);
      expect(restored.referer, original.referer);
    });

    test('a queue file written before these fields existed still loads', () {
      final restored = DownloadOptions.fromJson(const {
        'cookiesFromBrowser': 'firefox',
        'audioFormat': 'm4a',
      });

      expect(restored.cookiesFromBrowser, 'firefox');
      expect(restored.cookiesFile, isNull);
      expect(restored.userAgent, isNull);
      expect(restored.audioFormat, 'm4a');
    });
  });

  group('copyWith', () {
    test('clears a cookie file when passed a null-returning closure', () {
      const original = DownloadOptions(cookiesFile: r'C:\jars\cookies.txt');

      expect(original.copyWith(cookiesFile: () => null).cookiesFile, isNull);
    });

    test('leaves fields alone when the closure is omitted', () {
      const original = DownloadOptions(
        cookiesFile: r'C:\jars\cookies.txt',
        userAgent: 'Mozilla/5.0',
      );

      final updated = original.copyWith(audioOnly: true);

      expect(updated.cookiesFile, r'C:\jars\cookies.txt');
      expect(updated.userAgent, 'Mozilla/5.0');
      expect(updated.audioOnly, isTrue);
    });
  });
}
