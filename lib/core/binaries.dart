import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'paths.dart';

/// Standalone build — no Python install required on the user's machine.
const _ytDlpUrl =
    'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';

/// BtbN publishes rolling win64 builds; the zip nests binaries under `*/bin/`.
const _ffmpegUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/latest/'
    'download/ffmpeg-master-latest-win64-gpl.zip';

/// Resolved locations of the two external tools the app drives.
class BinarySet {
  const BinarySet({required this.ytDlp, required this.ffmpeg});

  final String ytDlp;
  final String ffmpeg;

  /// yt-dlp's `--ffmpeg-location` accepts the containing directory, which also
  /// lets it find `ffprobe.exe` sitting alongside.
  String get ffmpegDir => p.dirname(ffmpeg);
}

class BootstrapProgress {
  const BootstrapProgress(this.stage, [this.fraction]);

  final String stage;

  /// `null` when the server did not send a Content-Length, meaning the UI
  /// should show an indeterminate bar rather than a fake percentage.
  final double? fraction;
}

class BinaryManager {
  /// Returns the tool paths, or `null` if either is missing so the caller can
  /// route to first-run setup. Manual overrides from Settings win, which is the
  /// escape hatch for users who already have these on disk.
  Future<BinarySet?> resolve({
    String? ytDlpOverride,
    String? ffmpegOverride,
  }) async {
    final bin = await AppPaths.binDir();
    final ytDlp = _firstExisting([
      ytDlpOverride,
      p.join(bin.path, 'yt-dlp.exe'),
    ]);
    final ffmpeg = _firstExisting([
      ffmpegOverride,
      p.join(bin.path, 'ffmpeg.exe'),
    ]);
    if (ytDlp == null || ffmpeg == null) return null;
    return BinarySet(ytDlp: ytDlp, ffmpeg: ffmpeg);
  }

  /// Downloads both tools into the app's bin directory.
  ///
  /// Each file lands as `.part` and is renamed only once complete, so an
  /// interrupted setup can never leave a truncated executable that looks valid
  /// to [resolve].
  Future<BinarySet> bootstrap(void Function(BootstrapProgress) onProgress) async {
    final bin = await AppPaths.binDir();
    final ytDlpPath = p.join(bin.path, 'yt-dlp.exe');

    if (!File(ytDlpPath).existsSync()) {
      await _download(
        _ytDlpUrl,
        ytDlpPath,
        (f) => onProgress(BootstrapProgress('Downloading yt-dlp', f)),
      );
    }

    final ffmpegPath = p.join(bin.path, 'ffmpeg.exe');
    if (!File(ffmpegPath).existsSync()) {
      final zipPath = p.join((await AppPaths.tempRoot()).path, 'ffmpeg.zip');
      await _download(
        _ffmpegUrl,
        zipPath,
        (f) => onProgress(BootstrapProgress('Downloading FFmpeg', f)),
      );
      onProgress(const BootstrapProgress('Extracting FFmpeg'));
      await _extractFfmpeg(zipPath, bin.path);
      await File(zipPath).delete();
    }

    final resolved = await resolve();
    if (resolved == null) {
      throw const BinarySetupException(
        'Setup finished but the binaries are still missing from the bin folder.',
      );
    }
    return resolved;
  }

  /// `yt-dlp -U` replaces the executable in place. Site extractors break
  /// regularly, so this is the first thing to try when a download fails.
  Future<String> selfUpdate(BinarySet binaries) async {
    final result = await Process.run(
      binaries.ytDlp,
      ['-U'],
      stdoutEncoding: SystemEncoding(),
      stderrEncoding: SystemEncoding(),
    );
    final out = '${result.stdout}${result.stderr}'.trim();
    if (result.exitCode != 0) {
      throw BinarySetupException(
        out.isEmpty ? 'Update failed (exit ${result.exitCode}).' : out,
      );
    }
    return out.isEmpty ? 'yt-dlp is up to date.' : out;
  }

  Future<String> version(String exe, List<String> args) async {
    final result = await Process.run(exe, args,
        stdoutEncoding: SystemEncoding(), stderrEncoding: SystemEncoding());
    final out = (result.stdout as String).trim();
    return out.isEmpty ? 'unknown' : out.split('\n').first.trim();
  }

  String? _firstExisting(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty && File(c).existsSync()) return c;
    }
    return null;
  }

  Future<void> _download(
    String url,
    String destination,
    void Function(double?) onProgress,
  ) async {
    final client = http.Client();
    final partPath = '$destination.part';
    final part = File(partPath);
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw BinarySetupException(
          'Download failed with HTTP ${response.statusCode}: $url',
        );
      }
      final total = response.contentLength;
      final sink = part.openWrite();
      var received = 0;
      var lastReported = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          // Throttle to ~1% steps; chunk-rate setState would thrash the UI.
          if (total == null) {
            onProgress(null);
          } else if (received - lastReported > total / 100) {
            lastReported = received;
            onProgress(received / total);
          }
        }
      } finally {
        await sink.close();
      }
      await part.rename(destination);
    } on BinarySetupException {
      if (part.existsSync()) await part.delete();
      rethrow;
    } catch (e) {
      if (part.existsSync()) await part.delete();
      throw BinarySetupException('Could not download $url — $e');
    } finally {
      client.close();
    }
  }

  Future<void> _extractFfmpeg(String zipPath, String binPath) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final wanted = {'ffmpeg.exe', 'ffprobe.exe'};
      var found = 0;
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = p.basename(file.name);
        if (!wanted.contains(name)) continue;
        await File(p.join(binPath, name)).writeAsBytes(file.content);
        found++;
      }
      if (found == 0) {
        throw const BinarySetupException(
          'The FFmpeg archive did not contain ffmpeg.exe — the build layout may '
          'have changed. Set the path manually in Settings.',
        );
      }
    } finally {
      await input.close();
    }
  }
}

class BinarySetupException implements Exception {
  const BinarySetupException(this.message);

  final String message;

  @override
  String toString() => message;
}
