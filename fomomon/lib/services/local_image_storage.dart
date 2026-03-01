/// Cross-platform image storage.
///
/// **Usage**: Import this file at all call sites. The Dart compiler selects
/// the correct backend at compile time via the conditional export below:
///   - Native (Android / iOS): [local_image_storage_native.dart] — writes
///     bytes to `{docsDir}/images/{key}` via dart:io File.
///   - Web (Chrome / Safari): [local_image_storage_web.dart] — persists bytes
///     in IndexedDB (`fomomon_images` database) and caches them in a
///     `Map<String, Uint8List>` for synchronous access. Images survive tab
///     close, page reload, and PWA backgrounding.
///
/// **Startup**: call [LocalImageStorage.initStorage()] before runApp().
///   - Native: no-op.
///   - Web: opens IDB and pre-loads all stored entries into the in-memory
///     cache so [readBytes] stays synchronous.
///
/// **Interface** — all backends expose the same static API:
///
/// ```dart
///   static Future<void>     initStorage()
///     // Must be called once before runApp(). No-op on native.
///
///   static Future<String>   saveImage(Uint8List bytes, String key)
///     // → returns absolute path on native, 'web_img:{key}' on web.
///
///   static Future<String>   saveImageToPermanentLocation({
///     required String tempPath, required String userId,
///     required String siteId, required String captureMode,
///     required DateTime timestamp,
///   })
///     // Legacy entry point called by confirm_screen. On native, copies
///     // the file to the permanent images directory if it isn't there yet.
///     // On web, bytes are already in the store; returns tempPath as-is.
///
///   static Uint8List        readBytes(String path)
///     // Synchronous. Native: File.readAsBytesSync(). Web: cache lookup.
///
///   static bool             imageExists(String path)
///     // Synchronous. Native: File.existsSync(). Web: cache.containsKey().
///
///   static Future<void>     deleteImage(String path)
///     // Native: File.delete(). Web: cache.remove() + IDB.delete().
/// ```
///
/// **Migration call-map** (old dart:io → this cross-platform API):
///
/// ```dart
///   // BEFORE (display — native only)
///   Image.file(File(path), fit: BoxFit.cover)
///   // AFTER (all platforms)
///   final bytes = LocalImageStorage.readBytes(path);   // sync
///   Image.memory(bytes, fit: BoxFit.cover)
///
///   // BEFORE (read bytes for upload)
///   final bytes = await File(path).readAsBytes();
///   // AFTER
///   final bytes = LocalImageStorage.readBytes(path);   // sync; same bytes
///
///   // BEFORE (save after capture)
///   final file = await File(xfile.path).copy(permanentPath);
///   final savedPath = file.path;
///   // AFTER
///   final bytes = await xfile.readAsBytes();           // XFile cross-platform API
///   final savedPath = await LocalImageStorage.saveImage(bytes, key);
///
///   // BEFORE (delete on retake)
///   await File(path).delete();
///   // AFTER
///   await LocalImageStorage.deleteImage(path);
/// ```
export 'local_image_storage_native.dart'
    if (dart.library.html) 'local_image_storage_web.dart';
