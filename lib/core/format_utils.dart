/// Display helpers shared by the queue tiles and the format picker.
library;

const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

String formatBytes(num? bytes, {int decimals = 1}) {
  if (bytes == null || bytes <= 0) return '—';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : decimals;
  return '${value.toStringAsFixed(digits)} ${_units[unit]}';
}

String formatSpeed(double? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond <= 0) return '—';
  return '${formatBytes(bytesPerSecond)}/s';
}

/// `1:05:03` for hours, `5:03` otherwise. Used for both ETA and video length.
String formatDuration(num? seconds) {
  if (seconds == null || seconds < 0 || !seconds.isFinite) return '—';
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
