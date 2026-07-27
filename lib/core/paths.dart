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

  /// A fresh, empty directory for one download's partial files, so cancelling
  /// is just a recursive delete instead of guessing which `.part` files were
  /// ours.
  static Future<Directory> taskTempDir(String taskId) async {
    final dir = Directory(p.join((await tempRoot()).path, taskId));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    return _ensure(dir.path);
  }

  /// `%USERPROFILE%\Videos\VideoDownloader`.
  static Future<Directory> defaultOutputDir() async {
    final home = Platform.environment['USERPROFILE'];
    final base = home != null && home.isNotEmpty
        ? p.join(home, 'Videos')
        : (await getApplicationDocumentsDirectory()).path;
    return _ensure(p.join(base, 'VideoDownloader'));
  }

  static Future<Directory> _ensure(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
