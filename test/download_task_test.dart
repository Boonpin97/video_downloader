import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/models/download_options.dart';
import 'package:video_downloader/models/download_task.dart';

DownloadTask makeTask({
  String url = 'https://example.invalid/watch/abc',
  String selector = '720p',
  DownloadOptions options = const DownloadOptions(),
}) {
  return DownloadTask(
    id: DownloadTask.deriveId(url, selector),
    url: url,
    title: 'Example video',
    formatSelector: selector,
    formatLabel: '720p · mp4',
    options: options,
    outputDir: r'C:\Users\someone\Videos\VideoDownloader',
  );
}

void main() {
  group('deriveId', () {
    test('is stable across calls, so a resumed task finds its scratch dir', () {
      final a = DownloadTask.deriveId('https://example.invalid/x', '720p');
      final b = DownloadTask.deriveId('https://example.invalid/x', '720p');

      expect(a, b);
      expect(a, isNotEmpty);
    });

    test('separates different URLs and different qualities', () {
      final base = DownloadTask.deriveId('https://example.invalid/x', '720p');

      expect(
        DownloadTask.deriveId('https://example.invalid/y', '720p'),
        isNot(base),
      );
      expect(
        DownloadTask.deriveId('https://example.invalid/x', '1080p'),
        isNot(base),
      );
    });

    test('does not confuse a url/selector split', () {
      // A naive concatenation would make these two collide.
      expect(
        DownloadTask.deriveId('https://a/b', 'c'),
        isNot(DownloadTask.deriveId('https://a', 'b c')),
      );
    });
  });

  group('state predicates', () {
    test('paused is resumable and not terminal', () {
      final task = makeTask()..state = TaskState.paused;

      expect(task.isTerminal, isFalse);
      expect(task.isActive, isFalse);
      expect(task.canResume, isTrue);
      expect(task.canPause, isFalse);
    });

    test('a failed task can resume, since yt-dlp kept its partial data', () {
      final task = makeTask()..state = TaskState.failed;

      expect(task.canResume, isTrue);
      expect(task.isTerminal, isTrue);
    });

    test('an in-flight task can pause but not resume', () {
      final task = makeTask()..state = TaskState.downloading;

      expect(task.canPause, isTrue);
      expect(task.canResume, isFalse);
      expect(task.isActive, isTrue);
    });

    test('a queued task can be paused before it ever starts', () {
      expect(makeTask().canPause, isTrue);
    });

    test('completed exposes no pause or resume', () {
      final task = makeTask()..state = TaskState.completed;

      expect(task.canPause, isFalse);
      expect(task.canResume, isFalse);
    });
  });

  group('resetForRetry', () {
    test('keeps byte counters so the bar does not jump backwards', () {
      final task = makeTask()
        ..state = TaskState.paused
        ..downloadedBytes = 5000
        ..totalBytes = 10000
        ..errorMessage = 'boom';
      task.appendLog('some earlier noise');

      task.resetForRetry();

      expect(task.state, TaskState.queued);
      // yt-dlp resumes from disk, so progress must carry over.
      expect(task.downloadedBytes, 5000);
      expect(task.totalBytes, 10000);
      // Stale diagnostics from the previous attempt should not persist.
      expect(task.errorMessage, isNull);
      expect(task.log, isEmpty);
    });
  });

  group('serialisation', () {
    test('round-trips through JSON', () {
      final original = makeTask(
        options: const DownloadOptions(
          cookiesFromBrowser: 'firefox',
          writeSubtitles: true,
          subtitleLanguages: 'en,ms',
          rateLimit: '5M',
        ),
      )
        ..state = TaskState.paused
        ..downloadedBytes = 1234
        ..totalBytes = 9999
        ..sizeIsEstimated = true
        ..outputPath = r'C:\out\video.mp4';

      // Through a real encode/decode, not just the map, so anything
      // unserialisable would surface.
      final decoded = jsonDecode(jsonEncode(original.toJson()));
      final restored =
          DownloadTask.fromJson(Map<String, dynamic>.from(decoded as Map))!;

      expect(restored.id, original.id);
      expect(restored.url, original.url);
      expect(restored.title, original.title);
      expect(restored.formatSelector, original.formatSelector);
      expect(restored.formatLabel, original.formatLabel);
      expect(restored.outputDir, original.outputDir);
      expect(restored.state, TaskState.paused);
      expect(restored.downloadedBytes, 1234);
      expect(restored.totalBytes, 9999);
      expect(restored.sizeIsEstimated, isTrue);
      expect(restored.outputPath, r'C:\out\video.mp4');
      expect(restored.options.cookiesFromBrowser, 'firefox');
      expect(restored.options.writeSubtitles, isTrue);
      expect(restored.options.subtitleLanguages, 'en,ms');
      expect(restored.options.rateLimit, '5M');
    });

    test('an interrupted download comes back paused, not running', () {
      // Closing the app kills the process; the task must not claim to still be
      // downloading on next launch.
      for (final state in [
        TaskState.downloading,
        TaskState.merging,
        TaskState.queued,
      ]) {
        final task = makeTask()..state = state;
        expect(task.toJson()['state'], TaskState.paused.name,
            reason: '$state should persist as paused');
      }
    });

    test('finished states survive verbatim', () {
      for (final state in [
        TaskState.completed,
        TaskState.failed,
        TaskState.cancelled,
        TaskState.paused,
      ]) {
        final task = makeTask()..state = state;
        expect(task.toJson()['state'], state.name);
      }
    });

    test('drops entries with nothing to resume from', () {
      expect(DownloadTask.fromJson({'url': 'x', 'outputDir': 'y'}), isNull);
      expect(DownloadTask.fromJson({'id': 'a', 'outputDir': 'y'}), isNull);
      expect(DownloadTask.fromJson({'id': 'a', 'url': 'x'}), isNull);
      expect(DownloadTask.fromJson(const {}), isNull);
    });

    test('fills defaults for a partial record rather than failing', () {
      final restored = DownloadTask.fromJson({
        'id': 'abc',
        'url': 'https://example.invalid/x',
        'outputDir': r'C:\out',
      })!;

      expect(restored.title, 'Untitled video');
      expect(restored.formatSelector, 'bv*+ba/b');
      expect(restored.state, TaskState.paused);
      expect(restored.downloadedBytes, 0);
      expect(restored.options.audioFormat, 'mp3');
    });

    test('an unrecognised state falls back to paused', () {
      final restored = DownloadTask.fromJson({
        'id': 'abc',
        'url': 'https://example.invalid/x',
        'outputDir': r'C:\out',
        'state': 'teleporting',
      })!;

      expect(restored.state, TaskState.paused);
    });
  });
}
