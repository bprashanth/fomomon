/// Cross-platform cache for sites.json.
///
/// **Usage**: Import this file at call sites. The Dart compiler selects the
/// correct backend at compile time:
///   - Native (Android / iOS): [sites_cache_storage_native.dart] — reads/writes
///     `{docsDir}/cache/sites.json` via dart:io File.
///   - Web (Chrome / Safari): [sites_cache_storage_web.dart] — reads/writes a
///     SharedPreferences key so the JSON string persists across reloads.
///
/// **Key parameter**: on web the [key] is used as the SharedPreferences key,
/// allowing site_service ('sites_cache') and site_sync_service
/// ('sites_cache_sync') to maintain independent caches without overwriting
/// each other mid-session. On native both callers share the same underlying
/// file ({docsDir}/cache/sites.json), matching the pre-existing behaviour.
///
/// **Interface**:
///
/// ```dart
///   static Future<String?> read(String key)
///     // Returns the cached JSON string, or null if nothing is stored yet.
///
///   static Future<void> write(String key, String json)
///     // Persists [json] under [key].
/// ```
export 'sites_cache_storage_native.dart'
    if (dart.library.html) 'sites_cache_storage_web.dart';
