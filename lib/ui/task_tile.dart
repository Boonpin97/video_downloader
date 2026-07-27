import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/format_utils.dart';
import '../models/download_task.dart';
import '../state/queue_controller.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, required this.queue});

  final DownloadTask task;
  final QueueController queue;

  @override
  Widget build(BuildContext context) {
    // Each task is its own Listenable, so a fast progress stream rebuilds only
    // this tile rather than the whole queue.
    return ListenableBuilder(
      listenable: task,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.formatLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StateChip(state: task.state),
                ..._actions(context),
              ],
            ),
            if (!task.isTerminal) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: task.state == TaskState.merging ? null : task.progress,
              ),
              const SizedBox(height: 6),
              Text(_statusLine(), style: theme.textTheme.bodySmall),
            ],
            if (task.state == TaskState.completed && task.outputPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  p.basename(task.outputPath!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (task.state == TaskState.failed) _errorPanel(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    switch (task.state) {
      case TaskState.queued:
      case TaskState.downloading:
      case TaskState.merging:
        return [
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: () => queue.cancel(task),
          ),
        ];
      case TaskState.completed:
        return [
          IconButton(
            tooltip: 'Show in Explorer',
            icon: const Icon(Icons.folder_open),
            onPressed: task.outputPath == null
                ? null
                : () => _revealInExplorer(task.outputPath!),
          ),
          IconButton(
            tooltip: 'Remove from list',
            icon: const Icon(Icons.clear),
            onPressed: () => queue.remove(task),
          ),
        ];
      case TaskState.failed:
      case TaskState.cancelled:
        return [
          IconButton(
            tooltip: 'Retry',
            icon: const Icon(Icons.refresh),
            onPressed: () => queue.retry(task),
          ),
          IconButton(
            tooltip: 'Remove from list',
            icon: const Icon(Icons.clear),
            onPressed: () => queue.remove(task),
          ),
        ];
    }
  }

  Widget _errorPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.errorMessage ?? 'Download failed.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
          if (task.log.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('Details', style: theme.textTheme.bodySmall),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      task.errorTail.join('\n'),
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _statusLine() {
    switch (task.state) {
      case TaskState.queued:
        return 'Waiting…';
      case TaskState.merging:
        // The byte transfer is done but ffmpeg is still working. Saying so
        // explicitly avoids a bar that looks stuck at 100%.
        return 'Combining audio and video…';
      case TaskState.downloading:
        final total = task.totalBytes;
        // HLS gives no exact total, so the figure is marked as approximate
        // rather than presented as fact.
        final size = total == null
            ? formatBytes(task.downloadedBytes)
            : '${formatBytes(task.downloadedBytes)} / '
                '${task.sizeIsEstimated ? '~' : ''}${formatBytes(total)}';
        return [
          size,
          formatSpeed(task.speedBytesPerSecond),
          if (task.etaSeconds != null)
            'ETA ${formatDuration(task.etaSeconds)}',
        ].join('  ·  ');
      default:
        return '';
    }
  }

  /// `explorer /select,` opens the containing folder with the file highlighted.
  /// It exits with a non-zero code even on success, so the result is ignored.
  Future<void> _revealInExplorer(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      await Process.run('explorer.exe', ['/select,', path]);
    } else {
      await Process.run('explorer.exe', [p.dirname(path)]);
    }
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final TaskState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state) {
      TaskState.queued => ('Queued', scheme.onSurfaceVariant),
      TaskState.downloading => ('Downloading', scheme.primary),
      TaskState.merging => ('Merging', scheme.tertiary),
      TaskState.completed => ('Done', Colors.green.shade700),
      TaskState.failed => ('Failed', scheme.error),
      TaskState.cancelled => ('Cancelled', scheme.onSurfaceVariant),
    };

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
