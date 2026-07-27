import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(940, 720),
    minimumSize: Size(760, 540),
    center: true,
    title: 'Video Downloader',
    titleBarStyle: TitleBarStyle.normal,
  );
  unawaited(windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  }));

  // Settings are loaded before the first frame so the output directory and
  // concurrency limit are available to the widget tree immediately.
  final settings = await SettingsController.load();
  runApp(VideoDownloaderApp(settings: settings));
}
