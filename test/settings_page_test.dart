import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_downloader/core/binaries.dart';
import 'package:video_downloader/core/ytdlp_service.dart';
import 'package:video_downloader/state/bridge_controller.dart';
import 'package:video_downloader/state/queue_controller.dart';
import 'package:video_downloader/state/settings_controller.dart';
import 'package:video_downloader/ui/settings_page.dart';

void main() {
  testWidgets('Settings opens as a pushed route', (tester) async {
    // Mirrors the real tree: the app-wide settings sit above MaterialApp, but
    // the service providers are created inside the home route, below the
    // Navigator. A pushed route is a sibling of home, not a descendant, so
    // anything provided there has to be carried across explicitly.
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    final service = YtDlpService(
      const BinarySet(ytDlp: 'yt-dlp.exe', ffmpeg: 'ffmpeg.exe'),
    );
    final bridge = BridgeController();
    final queue = QueueController(service);
    addTearDown(() {
      bridge.dispose();
      queue.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settings,
        child: MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<YtDlpService>.value(value: service),
              ChangeNotifierProvider<BridgeController>.value(value: bridge),
              ChangeNotifierProvider<QueueController>.value(value: queue),
            ],
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => openSettings(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Cookie file'), findsOneWidget);

    // Further down the list, so it needs scrolling into view. Reaching it at
    // all proves the BridgeController lookup resolved too.
    final bridgeSwitch = find.text('Accept links from the browser extension');
    await tester.scrollUntilVisible(bridgeSwitch, 200,
        scrollable: find.byType(Scrollable).first);

    expect(bridgeSwitch, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
