/// Parsing for yt-dlp's machine-readable progress lines.
///
/// This is deliberately a pure function over a single line of stdout: it is the
/// one piece of real logic the app owns rather than delegates, and it can be
/// exercised in tests without spawning a process.
library;

/// The `--progress-template` we hand to yt-dlp.
///
/// Every field uses the `s` conversion rather than `d`. yt-dlp renders missing
/// values as the literal string `NA`, and `%(...)d` on a missing value produces
/// garbage or throws inside yt-dlp's own formatter. `s` always yields something
/// parseable, and [parseProgressLine] treats `NA` as unknown.
///
/// Fragment counts are included because on HLS — the most common case by far —
/// `total_bytes` is never known and `total_bytes_estimate` swings wildly as
/// yt-dlp re-extrapolates from the bytes seen so far. Fragments give a stable,
/// monotonic progress source instead. See [ProgressUpdate.fraction].
const progressTemplate = 'download:DLPROG|%(progress.status)s'
    '|%(progress.downloaded_bytes)s'
    '|%(progress.total_bytes)s'
    '|%(progress.total_bytes_estimate)s'
    '|%(progress.speed)s'
    '|%(progress.eta)s'
    '|%(progress.fragment_index)s'
    '|%(progress.fragment_count)s';

const _prefix = 'DLPROG|';

class ProgressUpdate {
  const ProgressUpdate({
    required this.status,
    required this.downloadedBytes,
    this.totalBytes,
    this.totalBytesEstimate,
    this.speedBytesPerSecond,
    this.etaSeconds,
    this.fragmentIndex,
    this.fragmentCount,
  });

  /// `downloading`, `finished`, or `error`.
  final String status;
  final int downloadedBytes;

  /// Exact size from a `Content-Length`. Null for HLS and DASH, where no single
  /// total exists.
  final int? totalBytes;

  /// yt-dlp's extrapolation from progress so far. Not monotonic.
  final int? totalBytesEstimate;

  final double? speedBytesPerSecond;
  final int? etaSeconds;
  final int? fragmentIndex;
  final int? fragmentCount;

  bool get isFinished => status == 'finished';

  /// Best available size for display, exact if we have it.
  int? get displayTotalBytes => totalBytes ?? totalBytesEstimate;

  /// Whether [displayTotalBytes] is a guess, so the UI can mark it with `~`.
  bool get isSizeEstimated => totalBytes == null && totalBytesEstimate != null;

  /// Download completion in `0.0..1.0`, or `null` when nothing reliable is
  /// known and the UI should show an indeterminate bar.
  ///
  /// Sources in order of trustworthiness:
  /// 1. exact byte total — precise and monotonic;
  /// 2. fragment counts — monotonic, and the only sane option on HLS;
  /// 3. the byte estimate — jittery, but better than no bar at all.
  double? get fraction {
    final exact = totalBytes;
    if (exact != null && exact > 0) {
      return (downloadedBytes / exact).clamp(0.0, 1.0);
    }

    final count = fragmentCount;
    final index = fragmentIndex;
    if (count != null && count > 0 && index != null && index >= 0) {
      return (index / count).clamp(0.0, 1.0);
    }

    final estimate = totalBytesEstimate;
    if (estimate != null && estimate > 0) {
      return (downloadedBytes / estimate).clamp(0.0, 1.0);
    }
    return null;
  }
}

/// Returns an update for a `DLPROG` line, or `null` for anything else —
/// ordinary yt-dlp log output, blank lines, or a malformed record.
///
/// Never throws: a partially-written line from a killed process must not take
/// down the stream listener.
ProgressUpdate? parseProgressLine(String line) {
  final trimmed = line.trim();
  final start = trimmed.indexOf(_prefix);
  if (start < 0) return null;

  final parts = trimmed.substring(start).split('|');
  // Fragment fields are read only when present, so a record from an older
  // yt-dlp that predates them still parses.
  if (parts.length < 7) return null;

  final status = parts[1].trim();
  if (status.isEmpty || status == 'NA') return null;

  return ProgressUpdate(
    status: status,
    downloadedBytes: _toInt(parts[2]) ?? 0,
    totalBytes: _positive(_toInt(parts[3])),
    totalBytesEstimate: _positive(_toInt(parts[4])),
    speedBytesPerSecond: _toDouble(parts[5]),
    etaSeconds: _toInt(parts[6]),
    fragmentIndex: parts.length > 7 ? _toInt(parts[7]) : null,
    fragmentCount: parts.length > 8 ? _positive(_toInt(parts[8])) : null,
  );
}

int? _positive(int? value) => (value != null && value > 0) ? value : null;

/// yt-dlp emits floats for byte counts often enough (`1234.0`) that parsing
/// through [double] and rounding is more reliable than [int.tryParse].
int? _toInt(String raw) => _toDouble(raw)?.round();

double? _toDouble(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value == 'NA' || value == 'None') return null;
  final parsed = double.tryParse(value);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  return parsed;
}
