/// Per-download switches, populated from Settings.
///
/// Each of these unblocks a distinct class of site, so they are surfaced in the
/// UI rather than hard-coded.
class DownloadOptions {
  const DownloadOptions({
    this.cookiesFromBrowser,
    this.cookiesFile,
    this.userAgent,
    this.referer,
    this.writeSubtitles = false,
    this.subtitleLanguages = 'en',
    this.audioOnly = false,
    this.audioFormat = 'mp3',
    this.rateLimit,
  });

  /// `chrome`, `edge`, `firefox`, `brave`… Reuses an existing browser login for
  /// sites that gate video behind an account. `null` disables cookie loading.
  ///
  /// Unreliable on Chromium browsers since Chrome 127: App-Bound Encryption
  /// leaves the cookie database unreadable by other processes, so reading it
  /// fails even with the browser closed. [cookiesFile] is the way around that.
  final String? cookiesFromBrowser;

  /// Path to an exported Netscape-format cookie jar (`cookies.txt`).
  ///
  /// Takes precedence over [cookiesFromBrowser] — with both set it would be
  /// unclear which session actually authenticated the request, and the explicit
  /// choice is the one worth honouring.
  final String? cookiesFile;

  /// Sent as `--user-agent`.
  ///
  /// Matters whenever cookies came from a browser: Cloudflare binds the
  /// `cf_clearance` cookie it issues after a challenge to the client IP *and*
  /// the User-Agent, so a mismatch throws away the captcha the user just
  /// solved. `null` leaves yt-dlp's own default in place.
  final String? userAgent;

  /// Sent as `--referer`, for sites that only serve media to requests that
  /// claim to come from their own player page.
  final String? referer;

  final bool writeSubtitles;
  final String subtitleLanguages;

  /// Extract the audio track and discard the video.
  final bool audioOnly;
  final String audioFormat;

  /// yt-dlp rate syntax, e.g. `5M` or `500K`. `null` means unthrottled.
  final String? rateLimit;

  /// Flags shared by both `probe` and `download`. Cookies and the headers that
  /// authenticate alongside them belong here because a gated video cannot even
  /// be inspected without them.
  List<String> get sharedArgs => [
        if (_isSet(cookiesFile))
          ...['--cookies', cookiesFile!]
        else if (_isSet(cookiesFromBrowser))
          ...['--cookies-from-browser', cookiesFromBrowser!],
        if (_isSet(userAgent)) ...['--user-agent', userAgent!],
        if (_isSet(referer)) ...['--referer', referer!],
      ];

  static bool _isSet(String? value) => value != null && value.trim().isNotEmpty;

  List<String> get downloadArgs => [
        if (rateLimit != null && rateLimit!.isNotEmpty) ...['-r', rateLimit!],
        if (writeSubtitles) ...[
          '--write-subs',
          '--write-auto-subs',
          '--sub-langs',
          subtitleLanguages,
          '--embed-subs',
        ],
        if (audioOnly) ...['-x', '--audio-format', audioFormat],
      ];

  Map<String, dynamic> toJson() => {
        'cookiesFromBrowser': cookiesFromBrowser,
        'cookiesFile': cookiesFile,
        'userAgent': userAgent,
        'referer': referer,
        'writeSubtitles': writeSubtitles,
        'subtitleLanguages': subtitleLanguages,
        'audioOnly': audioOnly,
        'audioFormat': audioFormat,
        'rateLimit': rateLimit,
      };

  /// Tolerant of missing or wrongly-typed keys so a hand-edited or
  /// older-version queue file degrades to defaults instead of failing to load.
  factory DownloadOptions.fromJson(Map<String, dynamic> json) {
    return DownloadOptions(
      cookiesFromBrowser: json['cookiesFromBrowser'] as String?,
      cookiesFile: json['cookiesFile'] as String?,
      userAgent: json['userAgent'] as String?,
      referer: json['referer'] as String?,
      writeSubtitles: json['writeSubtitles'] == true,
      subtitleLanguages: json['subtitleLanguages'] as String? ?? 'en',
      audioOnly: json['audioOnly'] == true,
      audioFormat: json['audioFormat'] as String? ?? 'mp3',
      rateLimit: json['rateLimit'] as String?,
    );
  }

  DownloadOptions copyWith({
    String? Function()? cookiesFromBrowser,
    String? Function()? cookiesFile,
    String? Function()? userAgent,
    String? Function()? referer,
    bool? writeSubtitles,
    String? subtitleLanguages,
    bool? audioOnly,
    String? audioFormat,
    String? Function()? rateLimit,
  }) {
    return DownloadOptions(
      cookiesFromBrowser: cookiesFromBrowser != null
          ? cookiesFromBrowser()
          : this.cookiesFromBrowser,
      cookiesFile: cookiesFile != null ? cookiesFile() : this.cookiesFile,
      userAgent: userAgent != null ? userAgent() : this.userAgent,
      referer: referer != null ? referer() : this.referer,
      writeSubtitles: writeSubtitles ?? this.writeSubtitles,
      subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
      audioOnly: audioOnly ?? this.audioOnly,
      audioFormat: audioFormat ?? this.audioFormat,
      rateLimit: rateLimit != null ? rateLimit() : this.rateLimit,
    );
  }
}
