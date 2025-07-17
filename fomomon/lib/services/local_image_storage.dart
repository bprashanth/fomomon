/// local_image_storage.dart
/// ----------------
/// Handles saving images to a permanent location on the device.
/// Exposes:
/// - saveImageToPermanentLocation(): String
///
/// The returned path is a full local path to the image.
///
/// Example:
/// final permanentPath = await LocalImageStorage.saveImageToPermanentLocation(
///    tempPath: widget.imagePath,
///    userId: widget.userId,
///    siteId: widget.site.id,
///    captureMode: widget.captureMode,
///    timestamp: DateTime.now(),
///  );

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class LocalImageStorage {
  static Future<String> saveImageToPermanentLocation({
    required String tempPath,
    required String userId,
    required String siteId,
    required String captureMode, // 'portrait' or 'landscape'
    required DateTime timestamp,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${docsDir.path}/images/$siteId');

    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final filename =
        '${userId}_${_formatTimestamp(timestamp)}_$captureMode.jpg';
    final newPath = p.join(imagesDir.path, filename);

    final tempFile = File(tempPath);
    final newFile = await tempFile.copy(newPath);
    return newFile.path; // return full local path
  }

  static String _formatTimestamp(DateTime ts) {
    return '${ts.year}-${_pad(ts.month)}-${_pad(ts.day)}_${_pad(ts.hour)}${_pad(ts.minute)}${_pad(ts.second)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
