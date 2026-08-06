import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/download_task.dart';
import 'paths.dart';

/// Persists the download queue so it survives closing the app.
///
/// Writes are whole-file and go through a `.tmp` rename, so a crash mid-write
/// cannot leave a truncated file that fails to parse on the next launch.
class QueueStore {
  static const _fileName = 'queue.json';

  Future<File> _file() async =>
      File(p.join((await AppPaths.supportDir()).path, _fileName));

  /// Serialised writes. Saves are triggered by state changes that can arrive in
  /// quick succession, and two concurrent writers would interleave.
  Future<void> _pending = Future.value();

  Future<void> save(List<DownloadTask> tasks) {
    return _pending = _pending.then((_) => _write(tasks)).catchError((_) {
      // A queue that cannot be saved must not take down the download that
      // triggered the save.
    });
  }

  Future<void> _write(List<DownloadTask> tasks) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    final payload = jsonEncode({
      'version': 1,
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
    await temp.writeAsString(payload);
    await temp.rename(file.path);
  }

  /// Returns the stored queue, or an empty list if there is nothing readable.
  ///
  /// Any failure is swallowed: a corrupt queue file should cost the user their
  /// history, not the ability to start the app.
  Future<List<DownloadTask>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return [];

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return [];
      final raw = decoded['tasks'];
      if (raw is! List) return [];

      final tasks = <DownloadTask>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final task =
            DownloadTask.fromJson(Map<String, dynamic>.from(entry));
        if (task != null) tasks.add(task);
      }
      return tasks;
    } catch (_) {
      return [];
    }
  }

  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }
}
