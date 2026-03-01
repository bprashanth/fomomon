/// Cross-platform raw file I/O utilities.
///
/// **Usage**: Import this file wherever low-level file bytes or strings need
/// to be read or written. The Dart compiler selects the backend at compile
/// time via the conditional export below:
///   - Native (Android / iOS): [file_bytes_io.dart] — wraps dart:io File
///     operations and path_provider's getApplicationDocumentsDirectory().
///   - Web (Chrome / Safari): [file_bytes_web.dart] — delegates readFileBytes
///     and fileExists to the in-memory LocalImageStorage; write / directory /
///     string operations are no-ops (web has no filesystem).
///
/// **Interface** — all backends expose the same top-level functions:
///
/// ```dart
///   Future<Uint8List> readFileBytes(String path)
///   bool              fileExists(String path)         // sync
///   Future<bool>      fileExistsAsync(String path)
///   Future<String>    readFileString(String path)     // '' on web
///   Future<void>      writeFileBytes(String path, List<int> bytes)  // no-op on web
///   Future<void>      writeFileString(String path, String content)  // no-op on web
///   Future<void>      ensureDirectory(String path)    // no-op on web
///   Future<String>    getDocsDirPath()                // '' on web
/// ```
///
/// **Migration call-map** (old dart:io → this cross-platform API):
///
/// ```dart
///   // BEFORE
///   final bytes = await File(path).readAsBytes();
///   // AFTER
///   final bytes = await readFileBytes(path);
///
///   // BEFORE
///   final exists = File(path).existsSync();
///   // AFTER
///   final exists = fileExists(path);
///
///   // BEFORE
///   final exists = await File(path).exists();
///   // AFTER
///   final exists = await fileExistsAsync(path);
///
///   // BEFORE
///   final content = await File(path).readAsString();
///   // AFTER
///   final content = await readFileString(path);       // '' on web
///
///   // BEFORE
///   await File(path).writeAsBytes(bytes);
///   // AFTER
///   await writeFileBytes(path, bytes);                // no-op on web
///
///   // BEFORE
///   await File(path).writeAsString(content);
///   // AFTER
///   await writeFileString(path, content);             // no-op on web
///
///   // BEFORE
///   await Directory(path).create(recursive: true);
///   // AFTER
///   await ensureDirectory(path);                      // no-op on web
///
///   // BEFORE
///   final docsDir = (await getApplicationDocumentsDirectory()).path;
///   // AFTER
///   final docsDir = await getDocsDirPath();           // '' on web
/// ```
///
/// **Web note**: `readFileBytes` and `fileExists` delegate to
/// `LocalImageStorage` (the in-memory store, keys prefixed `web_img:`).
/// They are used by upload_service to stream image bytes to S3 — this path
/// works correctly because capture_screen stores images in the same in-memory
/// store before upload. `readFileString`, write functions, and
/// `getDocsDirPath` all return empty / no-op on web because site_service
/// and site_sync_service use SharedPreferences for their JSON caches
/// (kIsWeb branches) rather than going through this utility.
export 'file_bytes_io.dart' if (dart.library.html) 'file_bytes_web.dart';
