import '../core/format_utils.dart';

/// One selectable stream from yt-dlp's `formats` array.
class FormatOption {
  const FormatOption({
    required this.formatId,
    this.ext,
    this.width,
    this.height,
    this.fps,
    this.vcodec,
    this.acodec,
    this.filesize,
    this.filesizeApprox,
    this.tbr,
    this.formatNote,
    this.protocol,
    this.hasDrm = false,
  });

  factory FormatOption.fromJson(Map<String, dynamic> json) {
    return FormatOption(
      formatId: '${json['format_id'] ?? ''}',
      ext: json['ext'] as String?,
      width: _int(json['width']),
      height: _int(json['height']),
      fps: _double(json['fps']),
      vcodec: json['vcodec'] as String?,
      acodec: json['acodec'] as String?,
      filesize: _int(json['filesize']),
      filesizeApprox: _int(json['filesize_approx']),
      tbr: _double(json['tbr']),
      formatNote: json['format_note'] as String?,
      protocol: json['protocol'] as String?,
      hasDrm: json['has_drm'] == true,
    );
  }

  final String formatId;
  final String? ext;
  final int? width;
  final int? height;
  final double? fps;
  final String? vcodec;
  final String? acodec;
  final int? filesize;
  final int? filesizeApprox;
  final double? tbr;
  final String? formatNote;
  final String? protocol;
  final bool hasDrm;

  /// yt-dlp marks a definitely-absent track with the literal string `none`.
  /// A *missing* key means unknown, not absent: many extractors omit codec
  /// information entirely while still returning a perfectly playable
  /// progressive file. Treating unknown as absent silently discards every
  /// format such a site offers, so only an explicit `none` counts as absence.
  bool get hasVideo => vcodec != 'none' && vcodec != '';
  bool get hasAudio => acodec != 'none' && acodec != '';

  /// True when the extractor reported nothing about codecs, so [hasVideo] and
  /// [hasAudio] are assumptions rather than facts.
  bool get codecsUnknown => vcodec == null && acodec == null;

  /// A stream that already carries both tracks, so no ffmpeg merge is needed.
  bool get isMuxed => hasVideo && hasAudio;
  bool get isAudioOnly => hasAudio && !hasVideo;

  /// Exact size when known, otherwise yt-dlp's estimate. Frequently `null` on
  /// HLS, where no single Content-Length exists.
  int? get size => filesize ?? filesizeApprox;

  String get resolutionLabel {
    if (isAudioOnly) return 'Audio only';
    if (height == null) return formatNote ?? 'Video';
    final base = '${height}p';
    final rate = fps;
    return (rate != null && rate >= 50) ? '$base${rate.round()}' : base;
  }

  String get codecLabel {
    // Nothing to report, so fall back to the container rather than inventing
    // codec names the extractor never supplied.
    if (codecsUnknown) return ext?.toUpperCase() ?? '—';
    final parts = <String>[];
    final v = vcodec;
    final a = acodec;
    if (v != null && v != 'none' && v.isNotEmpty) parts.add(v.split('.').first);
    if (a != null && a != 'none' && a.isNotEmpty) parts.add(a.split('.').first);
    return parts.isEmpty ? '—' : parts.join(' + ');
  }

  String get sizeLabel {
    final bytes = size;
    if (bytes == null) {
      // Fall back to bitrate, which HLS manifests almost always advertise.
      final rate = tbr;
      return rate == null ? '—' : '~${rate.round()} kbps';
    }
    return '${filesize == null ? '~' : ''}${formatBytes(bytes)}';
  }

  /// Sort key: bigger is better. Height dominates, bitrate breaks ties.
  double get qualityRank => (height ?? 0) * 10000 + (tbr ?? 0);

  static int? _int(Object? v) =>
      v is num ? v.round() : (v is String ? int.tryParse(v) : null);

  static double? _double(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
}
