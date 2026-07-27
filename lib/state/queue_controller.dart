import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/ytdlp_service.dart';
import '../models/download_task.dart';

/// Owns the download queue and enforces the concurrency limit.
class QueueController extends ChangeNotifier {
  QueueController(this._service, {int maxConcurrent = 2})
      : _maxConcurrent = maxConcurrent;

  final YtDlpService _service;
  final List<DownloadTask> _tasks = [];

  /// Tasks the user cancelled, so the process-exit handler can tell a kill
  /// apart from a genuine failure — killing yt-dlp also produces a non-zero
  /// exit code.
  final Set<String> _cancelled = {};

  int _maxConcurrent;
  int _running = 0;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _tasks.where((t) => t.isActive).length;
  int get queuedCount => _tasks.where((t) => t.state == TaskState.queued).length;

  set maxConcurrent(int value) {
    _maxConcurrent = value.clamp(1, 8);
    _pump();
    notifyListeners();
  }

  void add(DownloadTask task) {
    _tasks.insert(0, task);
    notifyListeners();
    _pump();
  }

  void retry(DownloadTask task) {
    _cancelled.remove(task.id);
    task.resetForRetry();
    notifyListeners();
    _pump();
  }

  void cancel(DownloadTask task) {
    if (task.isTerminal) return;
    _cancelled.add(task.id);
    final process = task.process;
    if (process != null) {
      // The exit handler in _run finishes the state transition and removes the
      // scratch directory; doing it here too would race with it.
      process.kill();
    } else {
      // Still queued, so no process exists to kill.
      task.setState(TaskState.cancelled);
      unawaited(_service.cleanupTemp(task.id));
      notifyListeners();
    }
  }

  void remove(DownloadTask task) {
    if (!task.isTerminal) cancel(task);
    _tasks.remove(task);
    _cancelled.remove(task.id);
    task.dispose();
    notifyListeners();
  }

  void clearFinished() {
    final done = _tasks.where((t) => t.isTerminal).toList();
    for (final task in done) {
      _tasks.remove(task);
      _cancelled.remove(task.id);
      task.dispose();
    }
    notifyListeners();
  }

  /// Starts as many queued tasks as the concurrency limit allows.
  void _pump() {
    while (_running < _maxConcurrent) {
      final next = _tasks.reversed.cast<DownloadTask?>().firstWhere(
            (t) => t!.state == TaskState.queued,
            orElse: () => null,
          );
      if (next == null) return;
      _running++;
      unawaited(_run(next));
    }
  }

  Future<void> _run(DownloadTask task) async {
    task.setState(TaskState.downloading);
    notifyListeners();
    try {
      final path = await _service.download(
        task,
        onStarted: (process) => task.process = process,
        onProgress: task.applyProgress,
        onLog: task.appendLog,
      );
      if (_cancelled.contains(task.id)) {
        task.setState(TaskState.cancelled);
      } else {
        task.setState(TaskState.completed, path: path);
      }
    } on YtDlpException catch (e) {
      // A cancelled download exits non-zero; that is not a failure to report.
      if (_cancelled.contains(task.id)) {
        task.setState(TaskState.cancelled);
      } else {
        for (final line in e.log) {
          task.appendLog(line);
        }
        task.setState(TaskState.failed, error: e.message);
      }
    } on ProcessException catch (e) {
      task.setState(
        TaskState.failed,
        error: 'Could not start yt-dlp: ${e.message}',
      );
    } catch (e) {
      if (_cancelled.contains(task.id)) {
        task.setState(TaskState.cancelled);
      } else {
        task.setState(TaskState.failed, error: '$e');
      }
    } finally {
      _cancelled.remove(task.id);
      _running--;
      notifyListeners();
      _pump();
    }
  }

  @override
  void dispose() {
    for (final task in _tasks) {
      task.process?.kill();
      task.dispose();
    }
    _tasks.clear();
    super.dispose();
  }
}
