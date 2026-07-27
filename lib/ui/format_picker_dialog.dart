import 'package:flutter/material.dart';

import '../core/format_utils.dart';
import '../models/format_option.dart';
import '../models/video_info.dart';

/// The result of the picker: `null` format means "best available", which lets
/// yt-dlp choose with its own `bv*+ba/b` logic.
class FormatChoice {
  const FormatChoice(this.format, this.label);

  final FormatOption? format;
  final String label;
}

Future<FormatChoice?> showFormatPicker(
  BuildContext context,
  VideoInfo info,
) {
  return showDialog<FormatChoice>(
    context: context,
    builder: (_) => _FormatPickerDialog(info: info),
  );
}

class _FormatPickerDialog extends StatefulWidget {
  const _FormatPickerDialog({required this.info});

  final VideoInfo info;

  @override
  State<_FormatPickerDialog> createState() => _FormatPickerDialogState();
}

class _FormatPickerDialogState extends State<_FormatPickerDialog> {
  /// `null` is the "Best available" row, which is preselected because it is the
  /// right answer for almost every download.
  FormatOption? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;

    // Muxed streams first — they need no merge and are the safest default —
    // then video-only, then audio-only.
    final muxed = info.muxedFormats;
    final videoOnly = info.videoOnlyFormats;
    final audioOnly = info.audioOnlyFormats;

    return AlertDialog(
      title: const Text('Choose quality'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(info: info),
            const Divider(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _row(
                      selected: _selected == null,
                      onTap: () => setState(() => _selected = null),
                      title: 'Best available',
                      subtitle:
                          'Highest quality video plus the best audio track',
                      trailing: '',
                      theme: theme,
                    ),
                    if (muxed.isNotEmpty)
                      _section('Video with audio', muxed, theme),
                    if (videoOnly.isNotEmpty)
                      _section(
                        'Video only — audio is merged in automatically',
                        videoOnly,
                        theme,
                      ),
                    if (audioOnly.isNotEmpty)
                      _section('Audio only', audioOnly, theme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            FormatChoice(
              _selected,
              _selected == null ? 'Best available' : _label(_selected!),
            ),
          ),
          icon: const Icon(Icons.download),
          label: const Text('Download'),
        ),
      ],
    );
  }

  Widget _section(String title, List<FormatOption> formats, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
        ),
        for (final f in formats)
          _row(
            selected: identical(_selected, f),
            onTap: () => setState(() => _selected = f),
            title: f.resolutionLabel,
            subtitle: '${f.ext ?? '—'} · ${f.codecLabel}',
            trailing: f.sizeLabel,
            theme: theme,
          ),
      ],
    );
  }

  Widget _row({
    required bool selected,
    required VoidCallback onTap,
    required String title,
    required String subtitle,
    required String trailing,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // A plain icon rather than a Radio: the rows live in several
            // sections but form one logical group, which the current Radio API
            // expresses awkwardly.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(trailing, style: theme.textTheme.bodySmall),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  String _label(FormatOption f) => '${f.resolutionLabel} · ${f.ext ?? ''}';
}

class _Header extends StatelessWidget {
  const _Header({required this.info});

  final VideoInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumb = info.thumbnail;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thumb != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              thumb,
              width: 128,
              height: 72,
              fit: BoxFit.cover,
              // A dead thumbnail URL must not break the picker.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        if (thumb != null) const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.title,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (info.uploader != null) info.uploader!,
                  if (info.durationSeconds != null)
                    formatDuration(info.durationSeconds),
                  if (info.isLive) 'LIVE',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
