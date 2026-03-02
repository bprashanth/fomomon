/// local_image_storage_native.dart
/// ----------------
/// Handles saving images to a permanent location on the device.
/// Exposes a cross-platform API shared with the web implementation:
///
/// - saveImage(Uint8List bytes, String key) → Future<String>
///   Saves bytes to {docsDir}/images/{key} and returns that path.
///
/// - saveImageToPermanentLocation(...) → Future<String>
///   Legacy method used by confirm_screen. If the path from saveImage() is
///   passed in, it is already permanent and returned as-is.
///
/// - readBytes(String path) → Uint8List
///   Synchronously reads bytes from the local filesystem.
///
/// - imageExists(String path) → bool
///   Returns true if the file exists on disk.
///
/// - deleteImage(String path) → Future<void>
///   Deletes the file from disk.

import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class LocalImageStorage {
  /// Always false on native — images are written directly to disk and are
  /// always available after initStorage() (which is a no-op here).
  static bool storageFallback = false;

  /// No-op on native — images are written directly to disk in [saveImage].
  /// Exists so call sites can call initStorage() without platform guards.
  static Future<void> initStorage() async {}

  /// Saves [bytes] under key [key] inside the permanent images directory.
  /// Returns the full local path.
  static Future<String> saveImage(Uint8List bytes, String key) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${docsDir.path}/images');
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final file = File('${imagesDir.path}/$key');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Legacy entry point used by confirm_screen after takePicture().
  /// If [tempPath] already lives inside the permanent images directory
  /// (meaning capture_screen saved it via saveImage()), return it immediately.
  /// Otherwise copy from [tempPath] to a new permanent location.
  static Future<String> saveImageToPermanentLocation({
    required String tempPath,
    required String userId,
    required String siteId,
    required String captureMode,
    required DateTime timestamp,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final permanentDir = '${docsDir.path}/images';

    // Already in permanent location — no copy needed.
    if (tempPath.startsWith(permanentDir)) return tempPath;

    // Legacy path: copy from a temp file to the permanent location.
    final imagesDir = Directory('$permanentDir/$siteId');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final filename =
        '${userId}_${_formatTimestamp(timestamp)}_$captureMode.jpg';
    final newPath = p.join(imagesDir.path, filename);
    final tempFile = File(tempPath);
    final newFile = await tempFile.copy(newPath);
    return newFile.path;
  }

  /// Synchronously reads bytes for [path] from the local filesystem.
  /// Used by confirm_screen to display the captured image and by
  /// file_bytes_io.dart for uploads.
  static Uint8List readBytes(String path) =>
      File(path).readAsBytesSync();

  /// Returns true if the file at [path] exists on disk.
  static bool imageExists(String path) => File(path).existsSync();

  /// Deletes the file at [path] from disk if it exists.
  static Future<void> deleteImage(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static String _formatTimestamp(DateTime ts) {
    return '${ts.year}-${_pad(ts.month)}-${_pad(ts.day)}_${_pad(ts.hour)}${_pad(ts.minute)}${_pad(ts.second)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
