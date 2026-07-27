/// Per-download switches, populated from Settings.
///
/// Each of these unblocks a distinct class of site, so they are surfaced in the
/// UI rather than hard-coded.
class DownloadOptions {
  const DownloadOptions({
    this.cookiesFromBrowser,
    this.writeSubtitles = false,
    this.subtitleLanguages = 'en',
    this.audioOnly = false,
    this.audioFormat = 'mp3',
    this.rateLimit,
  });

  /// `chrome`, `edge`, `firefox`, `brave`… Reuses an existing browser login for
  /// sites that gate video behind an account. `null` disables cookie loading.
  final String? cookiesFromBrowser;

  final bool writeSubtitles;
  final String subtitleLanguages;

  /// Extract the audio track and discard the video.
  final bool audioOnly;
  final String audioFormat;

  /// yt-dlp rate syntax, e.g. `5M` or `500K`. `null` means unthrottled.
  final String? rateLimit;

  /// Flags shared by both `probe` and `download`. Cookies belong here because a
  /// gated video cannot even be inspected without them.
  List<String> get sharedArgs => [
        if (cookiesFromBrowser != null && cookiesFromBrowser!.isNotEmpty)
          ...['--cookies-from-browser', cookiesFromBrowser!],
      ];

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

  DownloadOptions copyWith({
    String? Function()? cookiesFromBrowser,
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
      writeSubtitles: writeSubtitles ?? this.writeSubtitles,
      subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
      audioOnly: audioOnly ?? this.audioOnly,
      audioFormat: audioFormat ?? this.audioFormat,
      rateLimit: rateLimit != null ? rateLimit() : this.rateLimit,
    );
  }
}
