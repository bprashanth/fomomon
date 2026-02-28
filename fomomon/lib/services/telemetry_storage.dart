/// telemetry_storage.dart
/// ----------------------
/// Persists telemetry events in a JSON-encoded list in shared_preferences.
/// Capped at 200 events (FIFO ring buffer). Cleared after each flush.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TelemetryStorage {
  static const String _key = 'telemetry_buffer';
  static const int _maxEvents = 200;

  /// Append one event to the buffer. Drops the oldest event if the cap is hit.
  static Future<void> appendEvent(Map<String, dynamic> event) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final List<dynamic> list = raw != null ? jsonDecode(raw) : [];

      if (list.length >= _maxEvents) {
        list.removeAt(0); // drop oldest
      }
      list.add(event);

      await prefs.setString(_key, jsonEncode(list));
    } catch (_) {
      // Storage errors must never crash the app.
    }
  }

  /// Returns all buffered events and removes them from storage atomically.
  static Future<List<Map<String, dynamic>>> loadAndClear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];

      await prefs.remove(_key);

      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
