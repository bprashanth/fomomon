/// Web implementation of cross-platform file I/O utilities.
/// The browser has no filesystem; operations that write files are no-ops and
/// read operations delegate to LocalImageStorageWeb in-memory store.
/// Callers in site_service / site_sync_service use SharedPreferences for
/// caching instead of these file helpers, so most functions here are stubs.

import 'dart:typed_data';
import '../services/local_image_storage_web.dart';

/// Read image bytes from the in-memory store (path = 'web_img:{key}').
Future<Uint8List> readFileBytes(String path) async =>
    LocalImageStorage.readBytes(path);

/// Check whether an image key is present in the in-memory store.
bool fileExists(String path) => LocalImageStorage.imageExists(path);

/// Async variant — delegates to the sync check.
Future<bool> fileExistsAsync(String path) async =>
    LocalImageStorage.imageExists(path);

/// No filesystem on web — always returns empty string.
Future<String> readFileString(String path) async => '';

/// No filesystem on web — no-op.
Future<void> writeFileBytes(String path, List<int> bytes) async {}

/// No filesystem on web — no-op.
Future<void> writeFileString(String path, String content) async {}

/// No filesystem on web — no-op.
Future<void> ensureDirectory(String path) async {}

/// No docs directory on web — returns empty string.
Future<String> getDocsDirPath() async => '';
