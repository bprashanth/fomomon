/// Web implementation of LocalImageStorage backed by IndexedDB.
///
/// Images are stored in the browser's IndexedDB database (`fomomon_images`)
/// so they survive tab close, page reload, and PWA backgrounding — matching
/// the native behaviour where images live on disk.
///
/// Because IDB is async but [readBytes] must stay synchronous, a pre-load
/// cache pattern is used:
///   1. [initStorage] opens the IDB database and loads all stored entries into
///      the in-memory [_store] map before runApp().
///   2. [saveImage] writes to both [_store] (so readBytes works immediately)
///      and IDB (so data survives a reload).
///   3. [readBytes] reads from [_store] — always synchronous.
///   4. [deleteImage] removes from both [_store] and IDB.
///
/// Fallback: if IDB is unavailable (private browsing on Safari, browser
/// restrictions), [initStorage] catches the error and the app continues with
/// in-memory-only storage — images are lost on reload but the app does not
/// crash.
///
/// IDB schema:
///   database : fomomon_images  (version 1)
///   store    : images          (out-of-line keys, values = ArrayBuffer)
///   key      : raw filename string (no 'web_img:' prefix)

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:indexed_db';
import 'dart:typed_data';

class LocalImageStorage {
  static final Map<String, Uint8List> _store = {};
  static Database? _db;

  static const String _prefix = 'web_img:';
  static const String _dbName = 'fomomon_images';
  static const String _storeName = 'images';

  /// Opens the IDB database and pre-loads all stored image bytes into [_store]
  /// so [readBytes] stays synchronous. Call once before runApp().
  static Future<void> initStorage() async {
    try {
      _db = await html.window.indexedDB!.open(
        _dbName,
        version: 1,
        onUpgradeNeeded: (event) {
          final db = (event.target as dynamic).result as Database;
          if (!db.objectStoreNames!.contains(_storeName)) {
            db.createObjectStore(_storeName);
          }
        },
      );
      await _preloadFromIdb();
    } catch (e) {
      // IDB unavailable (e.g. private browsing on Safari) — fall back to
      // in-memory-only mode. Images will be lost on reload.
      print('local_image_storage_web: IDB unavailable, using in-memory only: $e');
    }
  }

  /// Reads all IDB entries into [_store] using an IDB cursor stream.
  static Future<void> _preloadFromIdb() async {
    if (_db == null) return;
    try {
      final txn = _db!.transaction(_storeName, 'readonly');
      final store = txn.objectStore(_storeName);
      await for (final cursor in store.openCursor()) {
        final key = cursor.key as String;
        final val = cursor.value;
        if (val is ByteBuffer) {
          _store[key] = Uint8List.view(val);
        } else if (val is Uint8List) {
          _store[key] = val;
        }
      }
    } catch (e) {
      print('local_image_storage_web: IDB preload failed: $e');
    }
  }

  /// Saves [bytes] in [_store] and in IDB under [key], returns 'web_img:{key}'.
  static Future<String> saveImage(Uint8List bytes, String key) async {
    _store[key] = bytes;
    if (_db != null) {
      try {
        final txn = _db!.transaction(_storeName, 'readwrite');
        txn.objectStore(_storeName).put(bytes.buffer, key);
        await txn.completed;
      } catch (e) {
        print('local_image_storage_web: IDB write failed for $key: $e');
      }
    }
    return '$_prefix$key';
  }

  /// Legacy entry point used by confirm_screen.
  /// On web, [tempPath] is already a 'web_img:{key}' path — return as-is.
  static Future<String> saveImageToPermanentLocation({
    required String tempPath,
    required String userId,
    required String siteId,
    required String captureMode,
    required DateTime timestamp,
  }) async {
    return tempPath;
  }

  /// Returns bytes for [path] ('web_img:{key}') from the in-memory cache.
  /// Returns an empty Uint8List if the key is not found.
  static Uint8List readBytes(String path) {
    final key =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    return _store[key] ?? Uint8List(0);
  }

  /// Returns true if [path] ('web_img:{key}') is present in the cache.
  static bool imageExists(String path) {
    if (!path.startsWith(_prefix)) return false;
    final key = path.substring(_prefix.length);
    return _store.containsKey(key);
  }

  /// Removes [path] from [_store] and from IDB.
  static Future<void> deleteImage(String path) async {
    final key =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    _store.remove(key);
    if (_db != null) {
      try {
        final txn = _db!.transaction(_storeName, 'readwrite');
        txn.objectStore(_storeName).delete(key);
        await txn.completed;
      } catch (e) {
        print('local_image_storage_web: IDB delete failed for $key: $e');
      }
    }
  }
}
