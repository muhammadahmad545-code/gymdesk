import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Launcher shortcuts (Mark attendance, Add member) and the home-screen widget, through a small
/// channel to MainActivity. Everything here is best effort: tests and old builds have no channel.
abstract final class QuickAccess {
  static const _channel = MethodChannel('dev.basalt.gymdesk/quick');
  static final _actions = StreamController<String>.broadcast();
  static String? _pending;
  static bool _listening = false;

  /// Shortcut or widget taps that arrive while the app is already open.
  static Stream<String> get actions => _actions.stream;

  static void init() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        _pending = call.arguments as String;
        _actions.add(_pending!);
      }
    });
  }

  /// The action that opened the app (or arrived while the home screen was not showing), once.
  static Future<String?> takeAction() async {
    final held = _pending;
    _pending = null;
    if (held != null) return held;
    try {
      return await _channel.invokeMethod<String>('takeAction');
    } catch (_) {
      return null;
    }
  }

  /// Marks an action from [actions] as handled.
  static void consumed() => _pending = null;

  static Future<void> installShortcuts() async {
    try {
      await _channel.invokeMethod<bool>('installShortcuts');
    } catch (_) {}
  }

  static Future<void> updateWidget({required String gym, required int checkins, required int due, required int overdue, required String revenue}) async {
    try {
      await _channel.invokeMethod<void>('updateWidget', {
        'json': jsonEncode({'gym': gym, 'checkins': checkins, 'due': due, 'overdue': overdue, 'revenue': revenue}),
      });
    } catch (_) {}
  }
}
