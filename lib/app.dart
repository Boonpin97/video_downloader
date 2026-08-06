import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/binaries.dart';
import 'core/ytdlp_service.dart';
import 'state/bridge_controller.dart';
import 'state/queue_controller.dart';
import 'state/settings_controller.dart';
import 'ui/first_run_page.dart';
import 'ui/home_page.dart';

class VideoDownloaderApp extends StatelessWidget {
  const VideoDownloaderApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3F6FE0));
    return ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        title: 'Video Downloader',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: scheme,
          useMaterial3: true,
          visualDensity: VisualDensity.compact,
        ),
        home: const _BinaryGate(),
      ),
    );
  }
}

/// Decides between first-run setup and the app proper.
///
/// The rest of the app can then assume a valid [BinarySet] exists, so no screen
/// below this point has to handle missing tools.
class _BinaryGate extends StatefulWidget {
  const _BinaryGate();

  @override
  State<_BinaryGate> createState() => _BinaryGateState();
}

class _BinaryGateState extends State<_BinaryGate> {
  final _manager = BinaryManager();
  final _bridge = BridgeController();
  BinarySet? _binaries;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
    _startBridgeIfEnabled();
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  /// Restores the listener across launches, so a user who turned the bridge on
  /// once does not have to revisit Settings every time they open the app.
  Future<void> _startBridgeIfEnabled() async {
    final settings = context.read<SettingsController>();
    if (!settings.bridgeEnabled) return;
    await _bridge.apply(
      enabled: true,
      token: await settings.ensureBridgeToken(),
    );
  }

  Future<void> _check() async {
    final settings = context.read<SettingsController>();
    final found = await _manager.resolve(
      ytDlpOverride: settings.ytDlpPath,
      ffmpegOverride: settings.ffmpegPath,
    );
    if (mounted) {
      setState(() {
        _binaries = found;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final binaries = _binaries;
    if (binaries == null) {
      return FirstRunPage(
        manager: _manager,
        onReady: (b) => setState(() => _binaries = b),
      );
    }

    final settings = context.read<SettingsController>();
    final service = YtDlpService(binaries);
    return MultiProvider(
      providers: [
        Provider<YtDlpService>.value(value: service),
        ChangeNotifierProvider<BridgeController>.value(value: _bridge),
        ChangeNotifierProvider(
          // Reload any queue left over from a previous session. Anything that
          // was mid-download comes back paused, ready to resume.
          create: (_) => QueueController(
            service,
            maxConcurrent: settings.maxConcurrent,
          )..restore(),
        ),
      ],
      child: const HomePage(),
    );
  }
}
