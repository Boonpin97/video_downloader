import 'package:flutter/material.dart';

import '../core/binaries.dart';

/// Shown when yt-dlp or FFmpeg are missing.
///
/// The tools are fetched rather than shipped as assets: it keeps the repo small
/// and guarantees a current extractor set on day one, and the app needs a
/// network connection to do its job anyway.
class FirstRunPage extends StatefulWidget {
  const FirstRunPage({
    super.key,
    required this.manager,
    required this.onReady,
  });

  final BinaryManager manager;
  final ValueChanged<BinarySet> onReady;

  @override
  State<FirstRunPage> createState() => _FirstRunPageState();
}

class _FirstRunPageState extends State<FirstRunPage> {
  BootstrapProgress _progress = const BootstrapProgress('Preparing…');
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final binaries = await widget.manager.bootstrap((p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) widget.onReady(binaries);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is BinarySetupException ? e.message : '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.download_for_offline_outlined,
                    size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 20),
                Text('One-time setup', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Video Downloader uses yt-dlp to find video streams and '
                  'FFmpeg to combine them into an MP4. Both are downloaded '
                  'once, into this app\'s own folder.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                if (_error == null) ...[
                  Text(_progress.stage, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _progress.fraction),
                  if (_progress.fraction != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${(_progress.fraction! * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                                color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
