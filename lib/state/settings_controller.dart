import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/link_server.dart';
import '../core/paths.dart';
import '../models/download_options.dart';

/// Browsers yt-dlp can pull cookies from, for login-gated sites.
const cookieBrowsers = ['chrome', 'edge', 'firefox', 'brave', 'opera', 'vivaldi'];

class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this._outputDir);

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fallback = (await AppPaths.defaultOutputDir()).path;
    return SettingsController._(
      prefs,
      prefs.getString(_kOutputDir) ?? fallback,
    );
  }

  static const _kOutputDir = 'outputDir';
  static const _kMaxConcurrent = 'maxConcurrent';
  static const _kCookieBrowser = 'cookieBrowser';
  static const _kCookieFile = 'cookieFile';
  static const _kUserAgent = 'userAgent';
  static const _kWriteSubs = 'writeSubtitles';
  static const _kSubLangs = 'subtitleLanguages';
  static const _kAudioOnly = 'audioOnly';
  static const _kAudioFormat = 'audioFormat';
  static const _kRateLimit = 'rateLimit';
  static const _kAlwaysBest = 'alwaysBest';
  static const _kBridgeEnabled = 'bridgeEnabled';
  static const _kBridgeToken = 'bridgeToken';
  static const _kYtDlpPath = 'ytDlpPath';
  static const _kFfmpegPath = 'ffmpegPath';

  final SharedPreferences _prefs;
  String _outputDir;

  String get outputDir => _outputDir;

  /// Two at once keeps the queue moving without starving any single download of
  /// bandwidth, which is what makes progress bars look stuck.
  int get maxConcurrent => _prefs.getInt(_kMaxConcurrent) ?? 2;

  String? get cookieBrowser => _prefs.getString(_kCookieBrowser);

  /// Exported `cookies.txt`. Overrides [cookieBrowser] when set.
  String? get cookieFile => _prefs.getString(_kCookieFile);

  /// Paired with the cookie jar: a session cleared through a Cloudflare
  /// challenge is only valid for the User-Agent that solved it.
  String? get userAgent => _prefs.getString(_kUserAgent);

  bool get writeSubtitles => _prefs.getBool(_kWriteSubs) ?? false;
  String get subtitleLanguages => _prefs.getString(_kSubLangs) ?? 'en';
  bool get audioOnly => _prefs.getBool(_kAudioOnly) ?? false;
  String get audioFormat => _prefs.getString(_kAudioFormat) ?? 'mp3';
  String? get rateLimit => _prefs.getString(_kRateLimit);

  /// Skip the format picker and take the best available stream.
  bool get alwaysBest => _prefs.getBool(_kAlwaysBest) ?? false;

  /// Whether the loopback listener the browser extension talks to is running.
  /// Off by default — an open port should be something the user asked for.
  bool get bridgeEnabled => _prefs.getBool(_kBridgeEnabled) ?? false;

  /// Shared secret for the extension. `null` until the bridge is first
  /// switched on; stable afterwards, so the user pastes it into the extension
  /// once and never again.
  String? get bridgeToken => _prefs.getString(_kBridgeToken);

  String? get ytDlpPath => _prefs.getString(_kYtDlpPath);
  String? get ffmpegPath => _prefs.getString(_kFfmpegPath);

  DownloadOptions get options => DownloadOptions(
        cookiesFromBrowser: cookieBrowser,
        cookiesFile: cookieFile,
        userAgent: userAgent,
        writeSubtitles: writeSubtitles,
        subtitleLanguages: subtitleLanguages,
        audioOnly: audioOnly,
        audioFormat: audioFormat,
        rateLimit: rateLimit,
      );

  Future<void> setOutputDir(String value) async {
    _outputDir = value;
    await _prefs.setString(_kOutputDir, value);
    notifyListeners();
  }

  Future<void> setMaxConcurrent(int value) =>
      _setInt(_kMaxConcurrent, value.clamp(1, 8));

  Future<void> setCookieBrowser(String? value) =>
      _setNullableString(_kCookieBrowser, value);

  Future<void> setCookieFile(String? value) =>
      _setNullableString(_kCookieFile, value);

  Future<void> setUserAgent(String? value) => _setNullableString(
      _kUserAgent, (value == null || value.trim().isEmpty) ? null : value.trim());

  Future<void> setWriteSubtitles(bool value) => _setBool(_kWriteSubs, value);

  Future<void> setSubtitleLanguages(String value) =>
      _setString(_kSubLangs, value.trim().isEmpty ? 'en' : value.trim());

  Future<void> setAudioOnly(bool value) => _setBool(_kAudioOnly, value);

  Future<void> setAudioFormat(String value) => _setString(_kAudioFormat, value);

  Future<void> setRateLimit(String? value) => _setNullableString(
      _kRateLimit, (value == null || value.trim().isEmpty) ? null : value.trim());

  Future<void> setAlwaysBest(bool value) => _setBool(_kAlwaysBest, value);

  Future<void> setBridgeEnabled(bool value) => _setBool(_kBridgeEnabled, value);

  /// Returns the existing secret, minting one the first time. Awaited by the
  /// caller so the token is persisted before it is shown to be copied.
  Future<String> ensureBridgeToken() async {
    final existing = bridgeToken;
    if (existing != null && existing.isNotEmpty) return existing;
    return regenerateBridgeToken();
  }

  /// Invalidates the old secret. Every extension holding it stops being able to
  /// send links, which is the point — it is the revoke button.
  Future<String> regenerateBridgeToken() async {
    final minted = LinkServer.generateToken();
    await _prefs.setString(_kBridgeToken, minted);
    notifyListeners();
    return minted;
  }

  Future<void> setYtDlpPath(String? value) =>
      _setNullableString(_kYtDlpPath, value);

  Future<void> setFfmpegPath(String? value) =>
      _setNullableString(_kFfmpegPath, value);

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  Future<void> _setInt(String key, int value) async {
    await _prefs.setInt(key, value);
    notifyListeners();
  }

  Future<void> _setString(String key, String value) async {
    await _prefs.setString(key, value);
    notifyListeners();
  }

  Future<void> _setNullableString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
    notifyListeners();
  }
}
