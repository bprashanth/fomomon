/// Native implementation of SitesCacheStorage.
///
/// All callers share the same file ({docsDir}/cache/sites.json) regardless
/// of the [key] argument. The [key] parameter exists only to satisfy the
/// shared interface; on native there is only ever one sites.json cache file.
import '../utils/file_bytes.dart';

class SitesCacheStorage {
  /// Returns the contents of {docsDir}/cache/sites.json, or null if the file
  /// does not exist yet.
  static Future<String?> read(String key) async {
    final docsDir = await getDocsDirPath();
    final cacheFile = '$docsDir/cache/sites.json';
    if (!await fileExistsAsync(cacheFile)) return null;
    final s = await readFileString(cacheFile);
    return s.isEmpty ? null : s;
  }

  /// Writes [json] to {docsDir}/cache/sites.json.
  static Future<void> write(String key, String json) async {
    final docsDir = await getDocsDirPath();
    await ensureDirectory('$docsDir/cache');
    await writeFileString('$docsDir/cache/sites.json', json);
  }
}
