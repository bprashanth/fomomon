/// Web implementation of SitesCacheStorage backed by SharedPreferences.
///
/// [key] is used directly as the SharedPreferences key so that different
/// callers (site_service, site_sync_service) can maintain independent caches.
import 'package:shared_preferences/shared_preferences.dart';

class SitesCacheStorage {
  /// Returns the JSON string stored under [key], or null if absent.
  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  /// Persists [json] under [key] in SharedPreferences.
  static Future<void> write(String key, String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json);
  }
}
