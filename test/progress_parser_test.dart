import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/core/progress_parser.dart';

void main() {
  group('parseProgressLine', () {
    test('parses a well-formed progress line', () {
      final update = parseProgressLine(
        'DLPROG|downloading|1048576|4194304|NA|524288.5|6|NA|NA',
      );

      expect(update, isNotNull);
      expect(update!.status, 'downloading');
      expect(update.downloadedBytes, 1048576);
      expect(update.totalBytes, 4194304);
      expect(update.speedBytesPerSecond, 524288.5);
      expect(update.etaSeconds, 6);
      expect(update.fraction, closeTo(0.25, 1e-9));
      expect(update.isSizeEstimated, isFalse);
      expect(update.isFinished, isFalse);
    });

    test('prefers fragment counts over a byte estimate on HLS', () {
      // Real HLS shape: total_bytes is always NA and the estimate swings
      // around, so fragments are the only monotonic source.
      final update = parseProgressLine(
        'DLPROG|downloading|272412|NA|34146048.0|200.6|26064|16|64',
      );

      expect(update!.totalBytes, isNull);
      expect(update.fragmentIndex, 16);
      expect(update.fragmentCount, 64);
      expect(update.fraction, closeTo(0.25, 1e-9));
      // The estimate is still what gets displayed as the size, flagged as such.
      expect(update.displayTotalBytes, 34146048);
      expect(update.isSizeEstimated, isTrue);
    });

    test('an exact byte total outranks fragment counts', () {
      final update =
          parseProgressLine('DLPROG|downloading|500|1000|NA|NA|NA|1|64');

      expect(update!.fraction, closeTo(0.5, 1e-9));
    });

    test('falls back to the byte estimate when no fragments are reported', () {
      final update =
          parseProgressLine('DLPROG|downloading|500|NA|2000|100|10|NA|NA');

      expect(update!.displayTotalBytes, 2000);
      expect(update.isSizeEstimated, isTrue);
      expect(update.fraction, closeTo(0.25, 1e-9));
    });

    test('reports an unknown total as null so the UI stays indeterminate', () {
      final update = parseProgressLine(
        'DLPROG|downloading|4096|NA|NA|NA|NA|NA|NA',
      );

      expect(update, isNotNull);
      expect(update!.downloadedBytes, 4096);
      expect(update.totalBytes, isNull);
      expect(update.displayTotalBytes, isNull);
      expect(update.fraction, isNull);
      expect(update.speedBytesPerSecond, isNull);
      expect(update.etaSeconds, isNull);
    });

    test('treats a zero total as unknown rather than dividing by zero', () {
      final update = parseProgressLine('DLPROG|downloading|10|0|0|0|0|0|0');

      expect(update!.totalBytes, isNull);
      expect(update.fragmentCount, isNull);
      expect(update.fraction, isNull);
    });

    test('handles the very first fragment record without dividing by zero', () {
      final update =
          parseProgressLine('DLPROG|downloading|1024|NA|17434368.0|200.6|26064|0|64');

      expect(update!.fraction, 0.0);
    });

    test('rounds float byte counts', () {
      final update = parseProgressLine(
        'DLPROG|downloading|1234.0|5678.9|NA|1.5|2.7|NA|NA',
      );

      expect(update!.downloadedBytes, 1234);
      expect(update.totalBytes, 5679);
      expect(update.etaSeconds, 3);
    });

    test('flags the finished status used to enter the merging state', () {
      // Taken from a real run: the final record carries an exact total even
      // though every preceding one did not.
      final update = parseProgressLine(
        'DLPROG|finished|22418060|22418060|NA|174340.6|NA|NA|NA',
      );

      expect(update!.isFinished, isTrue);
      expect(update.fraction, 1.0);
      expect(update.isSizeEstimated, isFalse);
    });

    test('clamps a total that undershoots the downloaded byte count', () {
      final update =
          parseProgressLine('DLPROG|downloading|150|100|NA|NA|NA|NA|NA');

      expect(update!.fraction, 1.0);
    });

    test('still parses a record from a yt-dlp without fragment fields', () {
      final update = parseProgressLine('DLPROG|downloading|500|1000|NA|50|10');

      expect(update, isNotNull);
      expect(update!.fragmentIndex, isNull);
      expect(update.fragmentCount, isNull);
      expect(update.fraction, closeTo(0.5, 1e-9));
    });

    test('ignores ordinary yt-dlp log output', () {
      expect(parseProgressLine('[download] Destination: video.mp4'), isNull);
      expect(parseProgressLine('[Merger] Merging formats into "out.mp4"'),
          isNull);
      expect(parseProgressLine('WARNING: something happened'), isNull);
      expect(parseProgressLine(''), isNull);
      expect(parseProgressLine('   '), isNull);
    });

    test('returns null instead of throwing on truncated or malformed lines', () {
      // A killed process can leave a half-written line on the stream.
      expect(parseProgressLine('DLPROG|downloading|123'), isNull);
      expect(parseProgressLine('DLPROG|'), isNull);
      expect(parseProgressLine('DLPROG|NA|NA|NA|NA|NA|NA|NA|NA'), isNull);
      expect(
        parseProgressLine('DLPROG|downloading|abc|def|ghi|jkl|mno|pqr|stu'),
        isNotNull,
      );
      expect(
        parseProgressLine('DLPROG|downloading|abc|def|ghi|jkl|mno|pqr|stu')!
            .downloadedBytes,
        0,
      );
    });

    test('finds the record even when yt-dlp prefixes the line', () {
      final update = parseProgressLine(
          '[download] DLPROG|downloading|10|100|NA|NA|NA|NA|NA');

      expect(update, isNotNull);
      expect(update!.fraction, closeTo(0.1, 1e-9));
    });
  });

  test('progressTemplate matches what the parser expects', () {
    // `%(...)d` on a missing value breaks yt-dlp's own formatter, and missing
    // values are routine on HLS. Guard the contract the parser depends on.
    expect(progressTemplate.contains(')d'), isFalse);
    expect(progressTemplate.startsWith('download:DLPROG|'), isTrue);
    // Nine fields, so eight separators. Drifting here would silently shift
    // every field index in the parser.
    expect('|'.allMatches(progressTemplate).length, 8);
    expect(progressTemplate.contains('fragment_index'), isTrue);
    expect(progressTemplate.contains('fragment_count'), isTrue);
  });
}
