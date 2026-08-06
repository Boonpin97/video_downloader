import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/queue_store.dart';
import '../core/ytdlp_service.dart';
import '../models/download_task.dart';

/// Outcome of queueing a URL, so the UI can explain what happened when the
/// request collides with something already in the list.
enum AddResult { added, resumedExisting, alreadyRunning }

/// Owns the download queue, enforces the concurrency limit, and persists itself.
class QueueController extends ChangeNotifier {
  QueueController(this._service, {int maxConcurrent = 2, QueueStore? store})
      : _maxConcurrent = maxConcurrent,
        _store = store ?? QueueStore();

  final YtDlpService _service;
  final QueueStore _store;
  final List<DownloadTask> _tasks = [];

  /// Tasks stopped on purpose, so the process-exit handler can tell an
  /// intentional kill from a genuine failure — killing yt-dlp also produces a
  /// non-zero exit code. The value records which stop it was, because a pause
  /// keeps partial data and a cancel discards it.
  final Map<String, TaskState> _stopping = {};

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

  /// Reloads the queue written by a previous session. Anything that was
  /// mid-flight comes back paused rather than auto-starting, so closing the app
  /// during a download does not surprise the user with traffic on next launch.
  Future<void> restore() async {
    if (_tasks.isNotEmpty) return;
    final restored = await _store.load();
    if (restored.isEmpty) return;
    _tasks.addAll(restored);
    notifyListeners();
  }

  AddResult add(DownloadTask task) {
    // The id is derived from the URL and format, so a repeat request lands on
    // the existing entry instead of a duplicate fighting over the same scratch
    // directory.
    final existing = _findById(task.id);
    if (existing != null) {
      if (existing.isActive || existing.state == TaskState.queued) {
        return AddResult.alreadyRunning;
      }
      resume(existing);
      return AddResult.resumedExisting;
    }

    _tasks.insert(0, task);
    _save();
    notifyListeners();
    _pump();
    return AddResult.added;
  }

  /// Stops the download but keeps everything yt-dlp has already fetched.
  void pause(DownloadTask task) {
    if (!task.canPause) return;
    final process = task.process;
    if (process != null) {
      // The exit handler in _run performs the state transition; doing it here
      // as well would race with it.
      _stopping[task.id] = TaskState.paused;
      process.kill();
    } else {
      // Still queued, so there is no process to stop.
      task.setState(TaskState.paused);
      _save();
      notifyListeners();
    }
  }

  /// Re-queues a paused, failed, or cancelled task. Its scratch directory is
  /// left untouched, so yt-dlp continues from where it stopped.
  void resume(DownloadTask task) {
    if (!task.canResume) return;
    _stopping.remove(task.id);
    task.resetForRetry();
    _save();
    notifyListeners();
    _pump();
  }

  /// Abandons the download and discards its partial data.
  void cancel(DownloadTask task) {
    if (task.isTerminal) return;
    final process = task.process;
    if (process != null) {
      _stopping[task.id] = TaskState.cancelled;
      process.kill();
    } else {
      task.setState(TaskState.cancelled);
      unawaited(_service.cleanupTemp(task.id));
      _save();
      notifyListeners();
    }
  }

  void remove(DownloadTask task) {
    if (!task.isTerminal && task.state != TaskState.paused) cancel(task);
    _tasks.remove(task);
    _stopping.remove(task.id);
    // Removing is the user discarding the download outright, so the partial
    // data goes too — otherwise it would linger with nothing referencing it.
    unawaited(_service.cleanupTemp(task.id));
    task.dispose();
    _save();
    notifyListeners();
  }

  void clearFinished() {
    for (final task in _tasks.where((t) => t.isTerminal).toList()) {
      _tasks.remove(task);
      _stopping.remove(task.id);
      unawaited(_service.cleanupTemp(task.id));
      task.dispose();
    }
    _save();
    notifyListeners();
  }

  DownloadTask? _findById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _save() => unawaited(_store.save(_tasks));

  /// Starts as many queued tasks as the concurrency limit allows.
  void _pump() {
    while (_running < _maxConcurrent) {
      DownloadTask? next;
      for (final task in _tasks.reversed) {
        if (task.state == TaskState.queued) {
          next = task;
          break;
        }
      }
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
      final stop = _stopping[task.id];
      if (stop != null) {
        _applyStop(task, stop);
      } else {
        task.setState(TaskState.completed, path: path);
        // Success: only the sidecar path file is left, and nothing will need
        // the scratch directory again.
        unawaited(_service.cleanupTemp(task.id));
      }
    } on YtDlpException catch (e) {
      final stop = _stopping[task.id];
      if (stop != null) {
        _applyStop(task, stop);
      } else {
        for (final line in e.log) {
          task.appendLog(line);
        }
        // Partial data is kept: a failure is often transient, and Retry then
        // continues instead of starting over.
        task.setState(TaskState.failed, error: e.message);
      }
    } on ProcessException catch (e) {
      task.setState(
        TaskState.failed,
        error: 'Could not start yt-dlp: ${e.message}',
      );
    } catch (e) {
      final stop = _stopping[task.id];
      if (stop != null) {
        _applyStop(task, stop);
      } else {
        task.setState(TaskState.failed, error: '$e');
      }
    } finally {
      _stopping.remove(task.id);
      _running--;
      _save();
      notifyListeners();
      _pump();
    }
  }

  void _applyStop(DownloadTask task, TaskState stop) {
    task.setState(stop);
    if (stop == TaskState.cancelled) {
      unawaited(_service.cleanupTemp(task.id));
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
