import 'format_option.dart';

/// The subset of `yt-dlp -J` output the UI cares about.
class VideoInfo {
  const VideoInfo({
    required this.id,
    required this.title,
    required this.formats,
    this.thumbnail,
    this.durationSeconds,
    this.uploader,
    this.extractor,
    this.isLive = false,
    this.webpageUrl,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    // With `--no-playlist` yt-dlp normally resolves to a single video, but some
    // extractors still hand back a playlist envelope. Take the first entry so a
    // page containing several clips downloads the primary one instead of
    // failing with a confusing "no formats" error.
    var node = json;
    if (node['_type'] == 'playlist') {
      final entries = node['entries'];
      if (entries is List && entries.isNotEmpty && entries.first is Map) {
        node = Map<String, dynamic>.from(entries.first as Map);
      }
    }

    final rawFormats = node['formats'];
    final formats = <FormatOption>[];
    if (rawFormats is List) {
      for (final f in rawFormats) {
        if (f is Map) {
          final option = FormatOption.fromJson(Map<String, dynamic>.from(f));
          // Storyboard "formats" are JPEG previews, not playable media.
          if (option.formatId.isEmpty) continue;
          if (option.protocol == 'mhtml') continue;
          if (!option.hasVideo && !option.hasAudio) continue;
          formats.add(option);
        }
      }
    }
    formats.sort((a, b) => b.qualityRank.compareTo(a.qualityRank));

    return VideoInfo(
      id: '${node['id'] ?? ''}',
      title: (node['title'] as String?)?.trim().isNotEmpty == true
          ? node['title'] as String
          : 'Untitled video',
      formats: formats,
      thumbnail: node['thumbnail'] as String?,
      durationSeconds: (node['duration'] as num?)?.toDouble(),
      uploader: (node['uploader'] ?? node['channel'] ?? node['extractor_key'])
          as String?,
      extractor: node['extractor'] as String?,
      isLive: node['is_live'] == true,
      webpageUrl: node['webpage_url'] as String?,
    );
  }

  final String id;
  final String title;
  final List<FormatOption> formats;
  final String? thumbnail;
  final double? durationSeconds;
  final String? uploader;
  final String? extractor;
  final bool isLive;
  final String? webpageUrl;

  /// True only when *every* stream is encrypted. A single clear format means
  /// there is still something worth downloading.
  bool get isDrmProtected =>
      formats.isNotEmpty && formats.every((f) => f.hasDrm);

  List<FormatOption> get downloadableFormats =>
      formats.where((f) => !f.hasDrm).toList();

  /// Streams that need no ffmpeg merge, best first.
  List<FormatOption> get muxedFormats =>
      downloadableFormats.where((f) => f.isMuxed).toList();

  List<FormatOption> get videoOnlyFormats =>
      downloadableFormats.where((f) => f.hasVideo && !f.hasAudio).toList();

  List<FormatOption> get audioOnlyFormats =>
      downloadableFormats.where((f) => f.isAudioOnly).toList();
}
