import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/binaries.dart';
import '../core/ytdlp_service.dart';
import '../state/queue_controller.dart';
import '../state/settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _manager = BinaryManager();
  late final TextEditingController _subLangs;
  late final TextEditingController _rateLimit;
  bool _updating = false;
  String? _ytDlpVersion;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    _subLangs = TextEditingController(text: settings.subtitleLanguages);
    _rateLimit = TextEditingController(text: settings.rateLimit ?? '');
    _loadVersion();
  }

  @override
  void dispose() {
    _subLangs.dispose();
    _rateLimit.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final service = context.read<YtDlpService>();
    try {
      final version =
          await _manager.version(service.binaries.ytDlp, ['--version']);
      if (mounted) setState(() => _ytDlpVersion = version);
    } catch (_) {
      if (mounted) setState(() => _ytDlpVersion = 'unavailable');
    }
  }

  Future<void> _update() async {
    final service = context.read<YtDlpService>();
    setState(() => _updating = true);
    try {
      final message = await _manager.selfUpdate(service.binaries);
      if (mounted) _snack(message);
      await _loadVersion();
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickOutputDir() async {
    final settings = context.read<SettingsController>();
    final chosen = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose where downloads are saved',
      initialDirectory: settings.outputDir,
    );
    if (chosen != null) await settings.setOutputDir(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final service = context.read<YtDlpService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _section('Downloads'),
          ListTile(
            title: const Text('Save downloads to'),
            subtitle: Text(settings.outputDir),
            trailing: const Icon(Icons.folder_open),
            onTap: _pickOutputDir,
          ),
          ListTile(
            title: const Text('Simultaneous downloads'),
            subtitle: const Text(
              'More at once splits your bandwidth between them',
            ),
            trailing: DropdownButton<int>(
              value: settings.maxConcurrent,
              items: [for (var i = 1; i <= 6; i++) i]
                  .map((i) =>
                      DropdownMenuItem(value: i, child: Text(i.toString())))
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                await settings.setMaxConcurrent(value);
                if (context.mounted) {
                  context.read<QueueController>().maxConcurrent = value;
                }
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Always use best quality'),
            subtitle: const Text('Skip the quality picker'),
            value: settings.alwaysBest,
            onChanged: settings.setAlwaysBest,
          ),
          ListTile(
            title: const Text('Speed limit'),
            subtitle: const Text('For example 5M or 500K. Empty means no limit'),
            trailing: SizedBox(
              width: 120,
              child: TextField(
                controller: _rateLimit,
                textAlign: TextAlign.end,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'none',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: settings.setRateLimit,
                onTapOutside: (_) => settings.setRateLimit(_rateLimit.text),
              ),
            ),
          ),

          _section('Site access'),
          ListTile(
            title: const Text('Use cookies from browser'),
            subtitle: const Text(
              'Lets the app reach videos that need you to be signed in. '
              'Sign in with that browser first.',
            ),
            trailing: DropdownButton<String?>(
              value: settings.cookieBrowser,
              hint: const Text('Off'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Off'),
                ),
                ...cookieBrowsers.map(
                  (b) => DropdownMenuItem<String?>(value: b, child: Text(b)),
                ),
              ],
              onChanged: settings.setCookieBrowser,
            ),
          ),

          _section('Output'),
          SwitchListTile(
            title: const Text('Audio only'),
            subtitle: Text(
              'Extract the sound and discard the video (${settings.audioFormat})',
            ),
            value: settings.audioOnly,
            onChanged: settings.setAudioOnly,
          ),
          if (settings.audioOnly)
            ListTile(
              title: const Text('Audio format'),
              trailing: DropdownButton<String>(
                value: settings.audioFormat,
                items: const ['mp3', 'm4a', 'opus', 'wav', 'flac']
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => v == null ? null : settings.setAudioFormat(v),
              ),
            ),
          SwitchListTile(
            title: const Text('Download subtitles'),
            subtitle: const Text('Embedded into the file when available'),
            value: settings.writeSubtitles,
            onChanged: settings.setWriteSubtitles,
          ),
          if (settings.writeSubtitles)
            ListTile(
              title: const Text('Subtitle languages'),
              subtitle: const Text('Comma separated, for example en,ms'),
              trailing: SizedBox(
                width: 140,
                child: TextField(
                  controller: _subLangs,
                  textAlign: TextAlign.end,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: settings.setSubtitleLanguages,
                  onTapOutside: (_) =>
                      settings.setSubtitleLanguages(_subLangs.text),
                ),
              ),
            ),

          _section('Tools'),
          ListTile(
            title: const Text('yt-dlp'),
            subtitle: Text(
              '${_ytDlpVersion ?? 'checking…'}\n${service.binaries.ytDlp}',
            ),
            isThreeLine: true,
            trailing: _updating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonal(
                    onPressed: _update,
                    child: const Text('Update'),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Sites change their players often. Updating yt-dlp fixes most '
              '"could not find a video" errors.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          ListTile(
            title: const Text('FFmpeg'),
            subtitle: Text(service.binaries.ffmpeg),
            trailing: IconButton(
              tooltip: 'Choose a different ffmpeg.exe',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final result = await FilePicker.pickFiles(
                  dialogTitle: 'Select ffmpeg.exe',
                  type: FileType.custom,
                  allowedExtensions: const ['exe'],
                );
                final path = result?.files.single.path;
                if (path == null || !File(path).existsSync()) return;
                await settings.setFfmpegPath(path);
                service.binaries = BinarySet(
                  ytDlp: service.binaries.ytDlp,
                  ffmpeg: path,
                );
                if (context.mounted) _snack('FFmpeg path updated.');
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
