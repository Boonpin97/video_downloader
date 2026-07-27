import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/progress_parser.dart';
import 'download_options.dart';
import 'format_option.dart';
import 'video_info.dart';

enum TaskState {
  queued,
  downloading,

  /// yt-dlp reported the byte transfer finished but ffmpeg is still muxing.
  /// Tracked separately so the UI does not sit at 100% looking hung.
  merging,
  completed,
  failed,
  cancelled,
}

/// A single queued download.
///
/// Each task is its own [ChangeNotifier] so a fast-ticking progress bar rebuilds
/// only its own tile instead of the whole queue.
class DownloadTask extends ChangeNotifier {
  DownloadTask({
    required this.id,
    required this.url,
    required this.info,
    required this.formatSelector,
    required this.formatLabel,
    required this.options,
    required this.outputDir,
  });

  final String id;
  final String url;
  final VideoInfo info;

  /// The `-f` expression, e.g. `137+bestaudio/best`.
  final String formatSelector;

  /// Human-readable version of the above, for the tile subtitle.
  final String formatLabel;
  final DownloadOptions options;
  final String outputDir;

  TaskState state = TaskState.queued;
  int downloadedBytes = 0;

  /// Best-known total for display. May be an estimate — see [sizeIsEstimated].
  int? totalBytes;
  bool sizeIsEstimated = false;
  double? speedBytesPerSecond;
  int? etaSeconds;
  String? outputPath;
  String? errorMessage;

  /// Completion as reported by the parser, which picks the most trustworthy of
  /// byte totals and fragment counts.
  double? _fraction;

  /// Rolling tail of yt-dlp output. Capped because a long HLS download emits
  /// thousands of lines and only the last few matter when diagnosing a failure.
  final List<String> log = [];
  static const _maxLogLines = 200;

  /// Live handle, used to kill the process on cancel.
  Process? process;

  String get title => info.title;

  bool get isActive =>
      state == TaskState.downloading || state == TaskState.merging;

  bool get isTerminal =>
      state == TaskState.completed ||
      state == TaskState.failed ||
      state == TaskState.cancelled;

  /// `null` renders an indeterminate bar — the honest display when nothing
  /// reliable about the total is known.
  double? get progress => state == TaskState.completed ? 1 : _fraction;

  void applyProgress(ProgressUpdate update) {
    downloadedBytes = update.downloadedBytes;
    totalBytes = update.displayTotalBytes ?? totalBytes;
    sizeIsEstimated = update.isSizeEstimated;
    _fraction = update.fraction ?? _fraction;
    speedBytesPerSecond = update.speedBytesPerSecond;
    etaSeconds = update.etaSeconds;
    // yt-dlp emits `finished` once per stream; with separate video and audio
    // that fires twice before the merge, which is exactly the window this state
    // is meant to cover.
    state = update.isFinished ? TaskState.merging : TaskState.downloading;
    notifyListeners();
  }

  void appendLog(String line) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) return;
    log.add(trimmed);
    if (log.length > _maxLogLines) log.removeRange(0, log.length - _maxLogLines);
  }

  void setState(TaskState next, {String? error, String? path}) {
    state = next;
    if (error != null) errorMessage = error;
    if (path != null) outputPath = path;
    if (isTerminal) {
      speedBytesPerSecond = null;
      etaSeconds = null;
      process = null;
    }
    notifyListeners();
  }

  /// Clears transient failure state so the task can be re-queued.
  void resetForRetry() {
    state = TaskState.queued;
    downloadedBytes = 0;
    totalBytes = null;
    sizeIsEstimated = false;
    _fraction = null;
    speedBytesPerSecond = null;
    etaSeconds = null;
    errorMessage = null;
    outputPath = null;
    log.clear();
    notifyListeners();
  }

  /// The tail of the log, for the expandable error panel.
  List<String> get errorTail =>
      log.length <= 15 ? log : log.sublist(log.length - 15);

  static String buildSelector(FormatOption? format, {required bool audioOnly}) {
    if (audioOnly) return 'bestaudio/best';
    if (format == null) return 'bv*+ba/b';
    // A muxed stream is already complete; anything video-only needs an audio
    // track attached, with `/<id>` as the fallback if no audio exists at all.
    return format.isMuxed
        ? format.formatId
        : '${format.formatId}+bestaudio/${format.formatId}';
  }
}
