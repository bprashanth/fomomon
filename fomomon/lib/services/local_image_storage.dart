/// Cross-platform image storage.
///
/// **Usage**: Import this file at all call sites. The Dart compiler selects
/// the correct backend at compile time via the conditional export below:
///   - Native (Android / iOS): [local_image_storage_native.dart] — writes
///     bytes to `{docsDir}/images/{key}` via dart:io File.
///   - Web (Chrome / Safari): [local_image_storage_web.dart] — holds bytes
///     in a static in-memory `Map<String, Uint8List>` keyed by a `web_img:`
///     prefix (e.g. `web_img:portrait_20240101_120000.jpg`).
///
/// **Interface** — all backends expose the same static API:
///
/// ```dart
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
///     // On web, the bytes are already in the store; returns tempPath as-is.
///
///   static Uint8List        readBytes(String path)
///     // Synchronous. Native: File.readAsBytesSync(). Web: map lookup.
///
///   static bool             imageExists(String path)
///     // Synchronous. Native: File.existsSync(). Web: map.containsKey().
///
///   static Future<void>     deleteImage(String path)
///     // Native: File.delete(). Web: map.remove().
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
///
/// **Web caveat — SESSION-SCOPED STORAGE**
///   Images are stored in-memory for the duration of the browser tab's
///   lifetime. Closing the tab, navigating away, or reloading the page
///   clears ALL images. This means:
///     - Unsent sessions whose images have not been uploaded will lose their
///       image data on reload, even though the session metadata in
///       SharedPreferences persists.
///     - The "offline-then-upload-later" pattern does NOT work on web with
///       this backend. Capture and upload must happen within the same session.
///   For persistent image storage on web, replace this backend with the
///   IndexedDB backend (Stage 1). See docs/v2/cross_platform_backends.md.
export 'local_image_storage_native.dart'
    if (dart.library.html) 'local_image_storage_web.dart';
