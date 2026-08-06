import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/link_server.dart';

/// Runs the browser bridge and exposes its state to the UI.
///
/// The listener is a background service with no visible surface of its own, so
/// a failure to bind — almost always a port already in use — has to be carried
/// here and shown in Settings rather than thrown into nowhere.
class BridgeController extends ChangeNotifier {
  BridgeController({LinkServer? server}) : _server = server ?? LinkServer();

  final LinkServer _server;

  String? _error;
  bool _busy = false;

  bool get isRunning => _server.isRunning;
  int get port => _server.boundPort ?? _server.port;

  /// Why the bridge is not running, or `null` if there is nothing wrong.
  String? get error => _error;

  /// Set while starting or stopping, so the toggle can be disabled instead of
  /// queueing up conflicting requests.
  bool get busy => _busy;

  Stream<IncomingLink> get links => _server.links;

  /// Brings the listener into line with the setting. Safe to call repeatedly.
  Future<void> apply({required bool enabled, required String token}) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (enabled) {
        await _server.start(token);
      } else {
        await _server.stop();
      }
    } on LinkServerException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_server.dispose());
    super.dispose();
  }
}
