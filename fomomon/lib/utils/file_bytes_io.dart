/// dart:io implementation of cross-platform file I/O utilities.
/// Used on Android, iOS, and desktop.

import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Read [path] as raw bytes.
Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

/// Return true if the file at [path] exists (synchronous).
bool fileExists(String path) => File(path).existsSync();

/// Return true if the file at [path] exists (asynchronous).
Future<bool> fileExistsAsync(String path) => File(path).exists();

/// Read [path] as a UTF-8 string.
Future<String> readFileString(String path) => File(path).readAsString();

/// Write [bytes] to [path], creating the file if necessary.
Future<void> writeFileBytes(String path, List<int> bytes) =>
    File(path).writeAsBytes(bytes);

/// Write [content] to [path], creating the file if necessary.
Future<void> writeFileString(String path, String content) =>
    File(path).writeAsString(content);

/// Ensure the directory at [path] exists, creating it recursively if needed.
Future<void> ensureDirectory(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) await dir.create(recursive: true);
}

/// Return the absolute path to the application documents directory.
Future<String> getDocsDirPath() async =>
    (await getApplicationDocumentsDirectory()).path;
