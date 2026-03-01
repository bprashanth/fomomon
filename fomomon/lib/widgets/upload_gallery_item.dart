import 'package:flutter/material.dart';
import '../models/captured_session.dart';
import '../services/local_image_storage.dart';

class UploadGalleryItem extends StatelessWidget {
  final CapturedSession session;
  final VoidCallback onTap;

  const UploadGalleryItem({
    super.key,
    required this.session,
    required this.onTap,
  });

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.year}-${_pad(timestamp.month)}-${_pad(timestamp.day)} '
        '${_pad(timestamp.hour)}:${_pad(timestamp.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Cross-platform image widget: uses Image.memory (reads from LocalImageStorage
  /// on both native and web) so that 'web_img:{key}' paths work in browsers.
  Widget _buildThumbnail(String path) {
    if (path.isEmpty) {
      return const Icon(Icons.image, color: Colors.grey, size: 40);
    }
    try {
      final bytes = LocalImageStorage.readBytes(path);
      if (bytes.isEmpty) {
        return const Icon(Icons.image, color: Colors.grey, size: 40);
      }
      return Image.memory(bytes, fit: BoxFit.cover);
    } catch (_) {
      return const Icon(Icons.broken_image, color: Colors.grey, size: 40);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E0E).withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(255, 20, 172, 243).withOpacity(0.25),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: const Color(0xFF1A4273)),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Container(
                width: 100,
                height: 100,
                color: Colors.grey[800],
                child: _buildThumbnail(session.portraitImagePath),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.siteId,
                      style: const TextStyle(
                        color: Color.fromARGB(255, 199, 220, 237),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(session.timestamp),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Arrow indicator
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                Icons.chevron_right,
                color: Color.fromARGB(255, 199, 220, 237),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
