import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/link_server.dart';
import '../core/ytdlp_service.dart';
import '../models/download_options.dart';
import '../models/download_task.dart';
import '../state/bridge_controller.dart';
import '../state/queue_controller.dart';
import '../state/settings_controller.dart';
import 'format_picker_dialog.dart';
import 'settings_page.dart';
import 'task_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();
  final _urlFocus = FocusNode();
  StreamSubscription<IncomingLink>? _linkSubscription;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _linkSubscription = context.read<BridgeController>().links.listen(_onLink);
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    _urlController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  /// Handles a link pushed over from the browser extension.
  ///
  /// The window is raised first: the user clicked the button in their browser
  /// and the quality picker is about to appear, so a dialog opening behind the
  /// browser would look like nothing happened.
  Future<void> _onLink(IncomingLink link) async {
    if (_probing) {
      _notify('Still checking the last link — try that one again in a moment.');
      return;
    }
    _urlController.text = link.url;
    await windowManager.show();
    await windowManager.focus();
    if (!mounted) return;
    await _fetch(link: link);
  }

  /// Resolve the URL, let the user pick a quality, then queue it.
  ///
  /// [link] carries the session captured by the extension, which overrides the
  /// cookie settings for this one download — the browser's live cookies beat
  /// whatever jar was configured globally.
  Future<void> _fetch({IncomingLink? link}) async {
    final url = (link?.url ?? _urlController.text).trim();
    if (url.isEmpty || _probing) return;

    final settings = context.read<SettingsController>();
    final service = context.read<YtDlpService>();
    final queue = context.read<QueueController>();
    final options = link == null
        ? settings.options
        : _optionsForLink(settings.options, link);

    setState(() => _probing = true);
    try {
      final info = await service.probe(url, options);
      if (!mounted) return;

      FormatChoice? choice;
      if (settings.alwaysBest || options.audioOnly) {
        choice = const FormatChoice(null, 'Best available');
      } else {
        choice = await showFormatPicker(context, info);
        if (choice == null) return; // user cancelled
      }

      final selector = DownloadTask.buildSelector(
        choice.format,
        audioOnly: options.audioOnly,
      );
      final result = queue.add(
        DownloadTask(
          id: DownloadTask.deriveId(url, selector),
          url: url,
          title: info.title,
          formatSelector: selector,
          formatLabel: options.audioOnly
              ? 'Audio only · ${options.audioFormat}'
              : choice.label,
          options: options,
          outputDir: settings.outputDir,
        ),
      );

      if (mounted) {
        switch (result) {
          case AddResult.alreadyRunning:
            _notify('That video is already in the queue.');
          case AddResult.resumedExisting:
            _notify('Already downloaded once — resuming that entry.');
          case AddResult.added:
            break;
        }
      }
      _urlController.clear();
      _urlFocus.requestFocus();
    } on YtDlpException catch (e) {
      if (mounted) _showError(e);
    } catch (e) {
      if (mounted) _showError(YtDlpException('$e'));
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  /// Layers the extension's session over the configured options.
  ///
  /// Each field only overrides when the extension actually supplied it, so a
  /// send from a site with no cookies still inherits whatever the user set up
  /// in Settings instead of silently dropping it.
  DownloadOptions _optionsForLink(DownloadOptions base, IncomingLink link) {
    return base.copyWith(
      cookiesFile: link.cookiesFile == null ? null : () => link.cookiesFile,
      userAgent: link.userAgent == null ? null : () => link.userAgent,
      referer: link.referer == null ? null : () => link.referer,
    );
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(YtDlpException e) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 8),
          action: e.log.isEmpty
              ? null
              : SnackBarAction(
                  label: 'Details',
                  onPressed: () => _showLogDialog(e),
                ),
        ),
      );
  }

  void _showLogDialog(YtDlpException e) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('yt-dlp output'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              e.log.join('\n'),
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _urlController.text = text;
      _urlController.selection =
          TextSelection.collapsed(offset: text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<QueueController>();
    final tasks = queue.tasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Downloader'),
        actions: [
          if (tasks.any((t) => t.isTerminal))
            TextButton.icon(
              onPressed: queue.clearFinished,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Clear finished'),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => openSettings(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _urlBar(context),
          const Divider(height: 1),
          Expanded(
            child: tasks.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: tasks.length,
                    itemBuilder: (_, i) =>
                        TaskTile(task: tasks[i], queue: queue),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _urlBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              focusNode: _urlFocus,
              autofocus: true,
              enabled: !_probing,
              onSubmitted: (_) => _fetch(),
              decoration: InputDecoration(
                hintText: 'Paste the address of the page with the video',
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 16),
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _probing ? null : _pasteFromClipboard,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _probing ? null : _fetch,
              icon: _probing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_probing ? 'Checking…' : 'Fetch'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined,
                size: 56, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('Nothing queued yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Paste the address of a page that plays a video, then pick a '
              'quality. Streams protected by DRM cannot be downloaded.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
