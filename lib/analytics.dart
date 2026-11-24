// Telemetry is permanently disabled in this build.
// All Google Analytics Measurement Protocol tokens and network calls have been removed.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'state.dart';

/// Event name and parameters type.
typedef AnalyticsEvent = (String, Map<String, Object>);

class Analytics extends ChangeNotifier {
  Analytics._();
  static final instance = Analytics._();

  /// Telemetry is permanently disabled.
  bool enabled = false;

  static String get _file => p.join(AppState.supportDir(), 'analytics.json');

  /// Starts the analytics service (no-op; purges legacy analytics cache).
  Future<void> start({List<AnalyticsEvent> Function()? snapshot}) async {
    try {
      final f = File(_file);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  /// Records an event (no-op).
  void event(String name, [Map<String, Object> params = const {}]) {}

  /// Sets telemetry status (no-op; stays disabled).
  Future<void> setEnabled(bool on) async {
    enabled = false;
    notifyListeners();
  }
}
