import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/binaries.dart';
import '../core/cookie_jar.dart';
import '../core/ytdlp_service.dart';
import '../state/bridge_controller.dart';
import '../state/queue_controller.dart';
import '../state/settings_controller.dart';

/// Opens Settings, carrying the providers across the route boundary.
///
/// The service providers are created inside the home route rather than above
/// `MaterialApp`, because they depend on binaries that are only resolved after
/// the first-run check. A pushed route is a *sibling* of home under the same
/// Navigator, not a descendant, so it cannot see them — the values have to be
/// read here, where they are still in scope, and re-provided to the new route.
void openSettings(BuildContext context) {
  final service = context.read<YtDlpService>();
  final bridge = context.read<BridgeController>();
  final queue = context.read<QueueController>();

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MultiProvider(
        providers: [
          Provider<YtDlpService>.value(value: service),
          ChangeNotifierProvider<BridgeController>.value(value: bridge),
          ChangeNotifierProvider<QueueController>.value(value: queue),
        ],
        child: const SettingsPage(),
      ),
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _manager = BinaryManager();
  late final TextEditingController _subLangs;
  late final TextEditingController _rateLimit;
  late final TextEditingController _userAgent;
  bool _updating = false;
  String? _ytDlpVersion;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    _subLangs = TextEditingController(text: settings.subtitleLanguages);
    _rateLimit = TextEditingController(text: settings.rateLimit ?? '');
    _userAgent = TextEditingController(text: settings.userAgent ?? '');
    _loadVersion();
  }

  @override
  void dispose() {
    _subLangs.dispose();
    _rateLimit.dispose();
    _userAgent.dispose();
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

  Future<void> _pickCookieFile() async {
    final settings = context.read<SettingsController>();
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select the exported cookies.txt',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final problem = CookieJar.validate(path);
    if (problem != null) {
      if (mounted) _snack(problem);
      return;
    }
    await settings.setCookieFile(path);
    if (mounted) _snack('Cookie file set. Downloads will use that session.');
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
          _cookieFileTile(settings),
          _hint(
            'For sites that make you sign in or solve a captcha, export a '
            'cookies.txt while the page is open in your browser and pick it '
            'here. This is the reliable option on Chrome and Edge, where '
            'reading cookies directly no longer works.',
          ),
          ListTile(
            enabled: settings.cookieFile == null,
            title: const Text('Or read cookies from a browser'),
            subtitle: Text(
              settings.cookieFile != null
                  ? 'Ignored while a cookie file is set'
                  : 'Works with Firefox. Chromium browsers block this since '
                      'Chrome 127.',
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
              onChanged:
                  settings.cookieFile != null ? null : settings.setCookieBrowser,
            ),
          ),
          ListTile(
            title: const Text('Browser identity'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _userAgent,
                maxLines: 2,
                minLines: 1,
                style: Theme.of(context).textTheme.bodySmall,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Default. Paste your browser\'s User-Agent here',
                  helperText: 'Must match the browser the cookies came from, '
                      'or a captcha you just passed will not count.',
                  helperMaxLines: 3,
                ),
                onSubmitted: settings.setUserAgent,
                onTapOutside: (_) => settings.setUserAgent(_userAgent.text),
              ),
            ),
          ),

          _section('Browser extension'),
          ..._bridgeTiles(settings, context.watch<BridgeController>()),

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
          _hint(
            'Sites change their players often. Updating yt-dlp fixes most '
            '"could not find a video" errors.',
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

  /// Shows the jar's filename rather than its full path — export tools bury
  /// these in Downloads, and the long path pushes the useful part off-screen.
  /// A jar that has since been deleted or moved is called out here, because
  /// yt-dlp's own error for it arrives late and reads like a network failure.
  Widget _cookieFileTile(SettingsController settings) {
    final path = settings.cookieFile;
    final missing = path != null && !File(path).existsSync();
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(
        missing ? Icons.error_outline : Icons.cookie_outlined,
        color: missing ? scheme.error : null,
      ),
      title: const Text('Cookie file'),
      subtitle: Text(
        path == null
            ? 'Not set'
            : missing
                ? '${p.basename(path)} — no longer on disk. Export it again.'
                : p.basename(path),
        style: missing ? TextStyle(color: scheme.error) : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (path != null)
            IconButton(
              tooltip: 'Stop using this cookie file',
              icon: const Icon(Icons.clear),
              onPressed: () => settings.setCookieFile(null),
            ),
          IconButton(
            tooltip: 'Choose a cookies.txt',
            icon: const Icon(Icons.folder_open),
            onPressed: _pickCookieFile,
          ),
        ],
      ),
      onTap: _pickCookieFile,
    );
  }

  /// The bridge's own switch, status, and pairing secret.
  ///
  /// The token is deliberately shown in full rather than masked: it exists to
  /// be copied into the extension's options page, and a hidden field would just
  /// mean revealing it every time anyway.
  List<Widget> _bridgeTiles(
    SettingsController settings,
    BridgeController bridge,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final token = settings.bridgeToken;

    return [
      SwitchListTile(
        title: const Text('Accept links from the browser extension'),
        subtitle: Text(
          bridge.error ??
              (settings.bridgeEnabled
                  ? 'Listening on 127.0.0.1:${bridge.port}'
                  : 'Off. The extension cannot reach the app.'),
          style: bridge.error != null ? TextStyle(color: scheme.error) : null,
        ),
        value: settings.bridgeEnabled,
        onChanged: bridge.busy ? null : _toggleBridge,
      ),
      if (settings.bridgeEnabled && token != null) ...[
        ListTile(
          title: const Text('Pairing key'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText(
              token,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (mounted) _snack('Pairing key copied.');
                },
              ),
              IconButton(
                tooltip: 'Generate a new key',
                icon: const Icon(Icons.refresh),
                onPressed: _regenerateToken,
              ),
            ],
          ),
        ),
        _hint(
          'Paste this into the extension\'s options page once. Generating a '
          'new key immediately stops any extension still holding the old one.',
        ),
      ],
    ];
  }

  Future<void> _toggleBridge(bool enabled) async {
    final settings = context.read<SettingsController>();
    final bridge = context.read<BridgeController>();

    await settings.setBridgeEnabled(enabled);
    await bridge.apply(
      enabled: enabled,
      token: await settings.ensureBridgeToken(),
    );
    // A port clash leaves the setting on but nothing listening, which would be
    // a lie. Roll it back so the switch matches reality.
    if (enabled && bridge.error != null) {
      await settings.setBridgeEnabled(false);
    }
  }

  Future<void> _regenerateToken() async {
    final settings = context.read<SettingsController>();
    final bridge = context.read<BridgeController>();

    final token = await settings.regenerateBridgeToken();
    // Restart so the listener checks against the new secret rather than the
    // one it was started with.
    await bridge.apply(enabled: false, token: token);
    await bridge.apply(enabled: true, token: token);
    if (mounted) _snack('New key generated. Update the extension.');
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
