import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Filesystem locations the app owns.
///
/// Everything writable lives under the per-user application support directory
/// rather than next to the executable. yt-dlp overwrites itself during `-U`,
/// which fails outright if the app was installed into Program Files.
class AppPaths {
  static Directory? _bin;
  static Directory? _temp;

  /// Where `yt-dlp.exe` and `ffmpeg.exe` live.
  static Future<Directory> binDir() async {
    return _bin ??= await _ensure(
      p.join((await getApplicationSupportDirectory()).path, 'bin'),
    );
  }

  /// Scratch space for in-progress downloads and downloaded archives.
  static Future<Directory> tempRoot() async {
    return _temp ??= await _ensure(
      p.join((await getApplicationSupportDirectory()).path, 'temp'),
    );
  }

  /// The directory holding one download's partial files.
  ///
  /// Deliberately *not* emptied: yt-dlp keeps its own `.part` and `.ytdl`
  /// fragment-state files here, and reusing them is exactly what lets a paused
  /// or failed download resume instead of starting over. Because the directory
  /// is per task, discarding a download is still a single recursive delete.
  static Future<Directory> taskTempDir(String taskId) async {
    return _ensure(p.join((await tempRoot()).path, taskId));
  }

  /// Root of the app's per-user storage, for the persisted queue.
  static Future<Directory> supportDir() => getApplicationSupportDirectory();

  /// The user's Downloads folder.
  ///
  /// Resolved through the Windows known-folder API rather than assuming
  /// `%USERPROFILE%\Downloads`, because Downloads is commonly relocated to
  /// another drive. The environment fallbacks only apply if that lookup fails.
  ///
  /// Only a default: [SettingsController] persists whatever the user picks.
  static Future<Directory> defaultOutputDir() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return _ensure(downloads.path);
    } catch (_) {
      // Known-folder lookup can fail on an unusual profile; fall through.
    }

    final home = Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      return _ensure(p.join(home, 'Downloads'));
    }
    return _ensure(
      p.join((await getApplicationDocumentsDirectory()).path, 'VideoDownloader'),
    );
  }

  static Future<Directory> _ensure(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
