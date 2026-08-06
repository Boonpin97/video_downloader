import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/download_options.dart';
import '../models/download_task.dart';
import '../models/video_info.dart';
import 'binaries.dart';
import 'paths.dart';
import 'progress_parser.dart';

/// Decoding yt-dlp's output must never throw on a stray byte, so malformed
/// sequences are replaced rather than fatal.
const _utf8Lenient = Utf8Codec(allowMalformed: true);
const _decoder = Utf8Decoder(allowMalformed: true);

/// Forces Python to line-buffer and to speak UTF-8.
///
/// Without `PYTHONUNBUFFERED`, yt-dlp running as a child process with no TTY
/// block-buffers stdout: progress arrives in one lump at the end, and the bar
/// appears frozen for the whole download. This is the single most important
/// detail in the whole integration.
const _childEnvironment = {
  'PYTHONUNBUFFERED': '1',
  'PYTHONIOENCODING': 'utf-8',
};

class YtDlpException implements Exception {
  YtDlpException(this.message, {this.log = const [], this.isDrm = false});

  final String message;
  final List<String> log;
  final bool isDrm;

  @override
  String toString() => message;
}

class YtDlpService {
  YtDlpService(this.binaries);

  BinarySet binaries;

  /// Options that apply to every invocation.
  ///
  /// `--ignore-config` matters more than it looks: without it a user's global
  /// `yt-dlp.conf` can inject `--quiet` or its own `-o`, silently breaking
  /// progress parsing and output-path detection in a way that is very hard to
  /// diagnose from inside the app.
  List<String> get _baseArgs => const [
        '--ignore-config',
        '--no-colors',
        '--no-playlist',
      ];

  /// Reads metadata and the available formats without downloading anything.
  Future<VideoInfo> probe(String url, DownloadOptions options) async {
    final result = await Process.run(
      binaries.ytDlp,
      [
        ..._baseArgs,
        '-J',
        '--no-warnings',
        ...options.sharedArgs,
        url,
      ],
      environment: _childEnvironment,
      stdoutEncoding: _utf8Lenient,
      stderrEncoding: _utf8Lenient,
    );

    final stdout = result.stdout as String;
    final stderr = result.stderr as String;

    if (result.exitCode != 0 || stdout.trim().isEmpty) {
      throw _interpretFailure(stderr, result.exitCode);
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(stdout.trim()) as Map<String, dynamic>;
    } on FormatException {
      throw YtDlpException(
        'yt-dlp returned output that could not be read as video metadata.',
        log: _tail(stderr),
      );
    }

    final info = VideoInfo.fromJson(json);

    if (info.isDrmProtected) {
      throw YtDlpException(
        'This video is DRM-protected, so it cannot be downloaded.',
        isDrm: true,
      );
    }
    if (info.downloadableFormats.isEmpty) {
      throw YtDlpException(
        'No downloadable video streams were found on that page.',
        log: _tail(stderr),
      );
    }
    return info;
  }

  /// Runs the download to completion, reporting progress as it goes.
  ///
  /// Throws [YtDlpException] on a non-zero exit. Returns the final file path.
  Future<String?> download(
    DownloadTask task, {
    required void Function(Process) onStarted,
    required void Function(ProgressUpdate) onProgress,
    required void Function(String) onLog,
  }) async {
    final tempDir = await AppPaths.taskTempDir(task.id);
    // yt-dlp writes the final path here after any merge/move. Using a sidecar
    // file rather than parsing it out of stdout keeps the progress stream clean
    // and survives the path containing pipes or newlines.
    final pathFile = File(p.join(tempDir.path, '_final_path.txt'));
    // Only this one file is cleared before a run. yt-dlp appends to it, so a
    // resumed download would otherwise read a stale path from an earlier
    // attempt. The `.part` and `.ytdl` files beside it are what make resuming
    // work and must survive.
    if (pathFile.existsSync()) await pathFile.delete();

    final args = <String>[
      ..._baseArgs,
      '--newline',
      '--progress',
      // Resume from whatever is already in the scratch directory. This is
      // yt-dlp's default, but stating it makes the dependency explicit.
      '--continue',
      '--progress-template', progressTemplate,
      '--ffmpeg-location', binaries.ffmpegDir,
      // Keep partial fragments inside the task's own temp directory so
      // cancelling is a single recursive delete rather than a guess at which
      // `.part` files belonged to us.
      '--paths', 'home:${task.outputDir}',
      '--paths', 'temp:${tempDir.path}',
      '-o', '%(title)s [%(id)s].%(ext)s',
      // Sanitises characters illegal on Windows (`:`, `?`, `|`, `*`) while
      // keeping titles readable, and caps length so long titles do not trip
      // MAX_PATH late in the download.
      '--windows-filenames',
      '--trim-filenames', '200',
      '--print-to-file', 'after_move:filepath', pathFile.path,
      if (!task.options.audioOnly) ...[
        '-f', task.formatSelector,
        '--merge-output-format', 'mp4',
      ],
      ...task.options.sharedArgs,
      ...task.options.downloadArgs,
      task.url,
    ];

    final process = await Process.start(
      binaries.ytDlp,
      args,
      environment: _childEnvironment,
      runInShell: false,
    );
    onStarted(process);

    final stderrLines = <String>[];

    final stdoutDone = process.stdout
        .transform(_decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final update = parseProgressLine(line);
      if (update != null) {
        onProgress(update);
      } else {
        onLog(line);
      }
    }).asFuture<void>();

    final stderrDone = process.stderr
        .transform(_decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderrLines.add(line);
      onLog(line);
    }).asFuture<void>();

    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    String? finalPath;
    if (pathFile.existsSync()) {
      final lines = (await pathFile.readAsString())
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) finalPath = lines.last;
    }

    // The scratch directory is deliberately left alone here. Whether the
    // partial data is worth keeping depends on *why* the process ended — a
    // pause or a network failure should be resumable, a cancel should not —
    // and only the queue knows that. It calls [cleanupTemp] when appropriate.
    if (exitCode != 0) {
      throw _interpretFailure(stderrLines.join('\n'), exitCode);
    }
    return finalPath;
  }

  /// Deletes a task's scratch directory, ignoring failures — a locked file
  /// during cleanup should never mask the download's actual outcome.
  Future<void> cleanupTemp(String taskId) async {
    final dir = Directory(p.join((await AppPaths.tempRoot()).path, taskId));
    await _cleanup(dir);
  }

  Future<void> _cleanup(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Ignored deliberately: see doc comment.
    }
  }

  /// Turns yt-dlp's stderr into something a user can act on.
  ///
  /// The raw text is still attached as [YtDlpException.log] for the expandable
  /// details panel; this only picks the headline.
  YtDlpException _interpretFailure(String stderr, int exitCode) {
    final lower = stderr.toLowerCase();
    final log = _tail(stderr);

    if (lower.contains('drm')) {
      return YtDlpException(
        'This video is DRM-protected, so it cannot be downloaded.',
        log: log,
        isDrm: true,
      );
    }
    if (lower.contains('sign in') ||
        lower.contains('log in') ||
        lower.contains('login required') ||
        lower.contains('private video') ||
        lower.contains('members-only') ||
        lower.contains('403')) {
      return YtDlpException(
        'The site refused access. Open the page in your browser, sign in or '
        'clear the captcha, then export a cookies.txt and set it under Site '
        'access in Settings.',
        log: log,
      );
    }
    if (lower.contains('unsupported url') ||
        lower.contains('unable to extract') ||
        lower.contains('no video formats') ||
        lower.contains('unable to download webpage')) {
      return YtDlpException(
        'Could not find a video on that page. Sites change often — try '
        'updating yt-dlp from Settings, which fixes most extraction failures.',
        log: log,
      );
    }
    if (lower.contains('ffmpeg') || lower.contains('postprocessing')) {
      return YtDlpException(
        'The download finished but merging the audio and video failed. '
        'Check that FFmpeg is present in Settings.',
        log: log,
      );
    }

    final headline = log.reversed.firstWhere(
      (l) => l.trim().toLowerCase().startsWith('error'),
      orElse: () => log.isEmpty ? '' : log.last,
    );
    return YtDlpException(
      headline.trim().isEmpty
          ? 'yt-dlp exited with code $exitCode.'
          : headline.trim(),
      log: log,
    );
  }

  List<String> _tail(String text, {int lines = 15}) {
    final all = text
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();
    return all.length <= lines ? all : all.sublist(all.length - lines);
  }
}
