/// Web implementation of LocalImageStorage.
///
/// OFFLINE CAVEAT — SESSION-SCOPED STORAGE ONLY!
///
/// Images cannot be stored in SharedPreferences (localStorage) because
/// SharedPreferences only accepts primitive types (String, int, bool, List,
/// Map), not raw binary data. Storing JPEG bytes as base64 would exceed
/// typical 5 MB localStorage limits for even a handful of photos.
///
/// Therefore, images are stored in an in-memory Map<String, Uint8List>
/// for the lifetime of the browser tab. Consequences:
///
///   1. Page reload → all image data is lost.
///   2. Unsent sessions whose images have not been uploaded will become
///      "broken" after a reload: the session record survives in localStorage,
///      but the image bytes referenced by portraitImagePath / landscapeImagePath
///      are gone.
///   3. The capture → upload flow MUST complete within a single browser
///      session (tab open). Do not close the tab between capture and upload.
///
/// "Offline" does not mean the same thing here as on native:
///   - Native: images on disk survive app restarts; upload can happen hours later.
///   - Web (this backend): images live only until the tab is closed / reloaded.
///
/// To enable true offline web support (persistent images across reloads),
/// replace this backend with the IndexedDB backend (Stage 1), which stores
/// binary blobs via the browser's IndexedDB API.
/// See docs/v2/cross_platform_backends.md for the Stage 1 outline.
///
/// Path convention: 'web_img:{key}' where key is the filename without a path
/// component (e.g. 'web_img:portrait_20240101_120000.jpg').

import 'dart:typed_data';

class LocalImageStorage {
  static final Map<String, Uint8List> _store = {};

  static const String _prefix = 'web_img:';

  /// Saves [bytes] in memory under [key] and returns 'web_img:{key}'.
  ///
  /// Storage is in-memory only. Data is lost when the tab is closed or reloaded!
  static Future<String> saveImage(Uint8List bytes, String key) async {
    _store[key] = bytes;
    return '$_prefix$key';
  }

  /// Legacy entry point used by confirm_screen.
  /// On web, [tempPath] is already a 'web_img:{key}' path from saveImage().
  /// The bytes are already in the store — just return the path as-is.
  static Future<String> saveImageToPermanentLocation({
    required String tempPath,
    required String userId,
    required String siteId,
    required String captureMode,
    required DateTime timestamp,
  }) async {
    return tempPath;
  }

  /// Returns bytes for the image stored under [path] ('web_img:{key}').
  /// Returns an empty Uint8List if the key is not found (e.g. after a reload).
  static Uint8List readBytes(String path) {
    final key =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    return _store[key] ?? Uint8List(0);
  }

  /// Returns true if [path] ('web_img:{key}') is present in the store.
  static bool imageExists(String path) {
    if (!path.startsWith(_prefix)) return false;
    final key = path.substring(_prefix.length);
    return _store.containsKey(key);
  }

  /// Removes [path] from the in-memory store.
  static Future<void> deleteImage(String path) async {
    final key =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    _store.remove(key);
  }
}
