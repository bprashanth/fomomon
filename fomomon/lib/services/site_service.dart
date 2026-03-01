/// site_service.dart
/// ----------------
/// Handles loading and parsing `sites.json` from a S3 bucket.
/// Exposes:
/// - fetchSitesAndPrefetchImages(): List<Site>
///
/// The list of sites object returned contains local paths to the reference
/// images on native, and 'web_img:' in-memory keys on web (fetched with auth).

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/site.dart';
import '../models/telemetry_event.dart';
import '../models/telemetry_pivots.dart';
import '../config/app_config.dart';
import '../data/guest_sites.dart';
import '../services/local_image_storage.dart';
import '../services/local_session_storage.dart';
import '../services/local_site_storage.dart';
import '../services/telemetry_service.dart';
import '../utils/log.dart';
import '../utils/file_bytes.dart';
import 'fetch_service.dart';

// SharedPreferences keys for web caching
const String _kSitesCacheKey = 'sites_cache';

class SiteService {
  /// Returns true if [url] points at this app's S3 bucket.
  static bool _isAppBucketUrl(String url) {
    final host = Uri.parse(url).host;
    return host ==
            '${AppConfig.bucketName}.s3.${AppConfig.region}.amazonaws.com' ||
        host == '${AppConfig.bucketName}.s3.amazonaws.com';
  }

  static Future<List<Site>> fetchSitesAndPrefetchImages({
    bool async = false,
  }) async {
    if (AppConfig.isGuestMode) {
      dLog("Guest mode: Loading guest sites");
      final guestSites = await _loadGuestSites();
      final localSites = await LocalSiteStorage.loadLocalSites();
      return _mergeSites(guestSites, localSites);
    }

    if (async) {
      try {
        final cachedSites = await _loadCachedSites();
        final localSites = await LocalSiteStorage.loadLocalSites();
        final mergedSites = _mergeSites(cachedSites, localSites);
        if (cachedSites.isNotEmpty) {
          dLog(
            "Async mode: Returning ${mergedSites.length} sites immediately",
          );
          _fetchAndCacheSitesInBackground();
          return mergedSites;
        }
      } catch (e) {
        dLog("Async mode: Failed to load cached sites: $e");
      }
    }

    final remoteSites = await _fetchSitesSynchronously();
    final localSites = await LocalSiteStorage.loadLocalSites();
    return _mergeSites(remoteSites, localSites);
  }

  static Future<List<Site>> _loadGuestSites() async {
    try {
      final data = jsonDecode(GuestSites.guestSitesJson);
      dLog("Loaded guest sites: $data");
      final List<Site> sites =
          (data['sites'] as List)
              .map((siteJson) => Site.fromJson(siteJson, data['bucket_root']))
              .toList();

      if (sites.isEmpty) {
        dLog('No guest sites found');
        return [];
      }

      dLog(
        "Copying guest site assets to local storage for ${sites.length} sites",
      );

      for (final site in sites) {
        if (site.localPortraitPath != null &&
            site.localPortraitPath!.startsWith('assets/')) {
          site.localPortraitPath = await _copyAssetToLocalStorage(
            site.localPortraitPath!,
            site.id,
            'portrait',
          );
        }
        if (site.localLandscapePath != null &&
            site.localLandscapePath!.startsWith('assets/')) {
          site.localLandscapePath = await _copyAssetToLocalStorage(
            site.localLandscapePath!,
            site.id,
            'landscape',
          );
        }
      }

      dLog("Loaded ${sites.length} guest sites with local paths");
      return sites;
    } catch (e) {
      dLog("Error loading guest sites: $e");
      return [];
    }
  }

  static Future<String> _copyAssetToLocalStorage(
    String assetPath,
    String siteId,
    String imageType,
  ) async {
    // On web there is no filesystem. Return the asset path as-is;
    // ghost images for guest sites will be skipped on web.
    if (kIsWeb) return assetPath;

    try {
      final docsDir = await getDocsDirPath();
      final guestDir = '$docsDir/cache/guest_sites';
      await ensureDirectory(guestDir);

      final filename = '${siteId}_$imageType.jpg';
      final localPath = '$guestDir/$filename';

      final byteData = await rootBundle.load(assetPath);
      await writeFileBytes(localPath, byteData.buffer.asUint8List());

      dLog("Copied asset $assetPath to $localPath");
      return localPath;
    } catch (e) {
      dLog("Error copying asset $assetPath: $e");
      return assetPath;
    }
  }

  static Future<List<Site>> _fetchSitesSynchronously() async {
    try {
      final root = AppConfig.getResolvedBucketRoot();
      String jsonStr;

      final cachedIds = await _loadCachedSiteIds();

      if (root.startsWith("http")) {
        final response = await FetchService.instance.fetch(
          AppConfig.bucketName,
          "${AppConfig.org}/sites.json",
        );
        if (response.statusCode != 200) throw Exception("HTTP error");
        jsonStr = response.body;

        await _cacheSitesJson(jsonStr);
      } else if (root.startsWith("file://")) {
        if (kIsWeb) throw Exception("file:// scheme not supported on web");
        final path =
            root.endsWith('/') ? '${root}sites.json' : '$root/sites.json';
        jsonStr = await readFileString(Uri.parse(path).toFilePath());
      } else {
        throw Exception("Unsupported bucketRoot scheme");
      }

      final data = jsonDecode(jsonStr);
      dLog("Fetched sites: $data");
      final List<Site> sites =
          (data['sites'] as List)
              .map((siteJson) => Site.fromJson(siteJson, data['bucket_root']))
              .toList();

      if (sites.isEmpty) {
        dLog('No sites found in sites.json');
        return [];
      }

      _logSitesChange(sites, cachedIds);
      await _handleSiteDeletions(sites, cachedIds);

      dLog("Ensuring cached images for ${sites.length} sites");

      for (final site in sites) {
        if (site.referenceLandscape.isEmpty ||
            site.referencePortrait.isEmpty ||
            site.bucketRoot.isEmpty) {
          dLog(
            'Skipping site ${site.id} - missing reference images or bucket root',
          );
          continue;
        }

        String getFileName(String path) {
          final uri = Uri.parse(path);
          return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : path;
        }

        final landscapeUrl =
            '${site.bucketRoot.endsWith('/') ? site.bucketRoot : '${site.bucketRoot}/'}${site.referenceLandscape}';
        final portraitUrl =
            '${site.bucketRoot.endsWith('/') ? site.bucketRoot : '${site.bucketRoot}/'}${site.referencePortrait}';

        final landscapeFileName = getFileName(site.referenceLandscape);
        final portraitFileName = getFileName(site.referencePortrait);

        site.localPortraitPath = await _ensureCachedImage(
          remoteUrl: portraitUrl,
          remoteFileName: portraitFileName,
          siteId: site.id,
          orientation: 'portrait',
        );

        site.localLandscapePath = await _ensureCachedImage(
          remoteUrl: landscapeUrl,
          remoteFileName: landscapeFileName,
          siteId: site.id,
          orientation: 'landscape',
        );

        dLog(
          "[site_service]: Cached images for site ${site.id}, portrait: ${site.localPortraitPath}, landscape: ${site.localLandscapePath}",
        );
      }

      await _updateCachedSitesWithLocalPaths(sites, data['bucket_root']);

      return sites;
    } catch (e) {
      dLog("Failed to fetch sites from network: $e");
      TelemetryService.instance.log(
        TelemetryLevel.error,
        TelemetryPivot.siteFetchFailed,
        'Failed to fetch sites.json from network',
        error: e,
      );
      dLog("Attempting to load cached sites.json");

      try {
        final cachedSites = await _loadCachedSites();
        if (cachedSites.isNotEmpty) {
          dLog("Successfully loaded ${cachedSites.length} sites from cache");
          TelemetryService.instance.log(
            TelemetryLevel.warning,
            TelemetryPivot.siteFetchCacheFallback,
            'Fell back to cached sites.json (${cachedSites.length} sites)',
          );
          return cachedSites;
        }
      } catch (cacheError) {
        dLog("Failed to load cached sites: $cacheError");
      }

      dLog("No cached sites available, returning empty list");
      return [];
    }
  }

  static Future<void> _fetchAndCacheSitesInBackground() async {
    try {
      dLog("Background fetch: Starting to fetch fresh sites data");

      final root = AppConfig.getResolvedBucketRoot();
      if (!root.startsWith("http")) {
        dLog("Background fetch: Skipping non-HTTP path");
        return;
      }

      final response = await FetchService.instance.fetch(
        AppConfig.bucketName,
        "${AppConfig.org}/sites.json",
      );
      if (response.statusCode != 200) {
        dLog("Background fetch: HTTP error ${response.statusCode}");
        return;
      }

      final cachedIds = await _loadCachedSiteIds();

      await _cacheSitesJson(response.body);
      dLog("Background fetch: Successfully cached fresh sites data");

      final data = jsonDecode(response.body);
      final freshSites =
          (data['sites'] as List)
              .map(
                (s) => Site.fromJson(
                  s as Map<String, dynamic>,
                  data['bucket_root'] as String,
                ),
              )
              .toList();
      _logSitesChange(freshSites, cachedIds);
      await _handleSiteDeletions(freshSites, cachedIds);

      _prefetchImagesInBackground(response.body);
    } catch (e) {
      dLog("Background fetch: Failed to fetch fresh sites data: $e");
    }
  }

  static Future<void> _prefetchImagesInBackground(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr);
      final List<Site> sites =
          (data['sites'] as List)
              .map((siteJson) => Site.fromJson(siteJson, data['bucket_root']))
              .toList();

      dLog(
        "Background prefetch: Starting to prefetch images for ${sites.length} sites",
      );

      for (final site in sites) {
        if (site.referenceLandscape.isEmpty ||
            site.referencePortrait.isEmpty ||
            site.bucketRoot.isEmpty) {
          continue;
        }

        String getFileName(String path) {
          final uri = Uri.parse(path);
          return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : path;
        }

        final landscapeUrl =
            '${site.bucketRoot.endsWith('/') ? site.bucketRoot : '${site.bucketRoot}/'}${site.referenceLandscape}';
        final portraitUrl =
            '${site.bucketRoot.endsWith('/') ? site.bucketRoot : '${site.bucketRoot}/'}${site.referencePortrait}';

        final landscapeFileName = getFileName(site.referenceLandscape);
        final portraitFileName = getFileName(site.referencePortrait);

        site.localLandscapePath = await _ensureCachedImage(
          remoteUrl: landscapeUrl,
          remoteFileName: landscapeFileName,
          siteId: site.id,
          orientation: 'landscape',
        );
        site.localPortraitPath = await _ensureCachedImage(
          remoteUrl: portraitUrl,
          remoteFileName: portraitFileName,
          siteId: site.id,
          orientation: 'portrait',
        );

        dLog("Background prefetch: Cached images for site ${site.id}");
      }

      await _updateCachedSitesWithLocalPaths(sites, data['bucket_root']);
      dLog("Background prefetch: Completed for all sites");
    } catch (e) {
      dLog("Background prefetch: Failed to prefetch images: $e");
    }
  }

  /// Downloads and caches a ghost reference image.
  ///
  /// On native: downloads to {docsDir}/ghosts/{siteId}/{remoteFileName} and
  /// returns the local file path. Subsequent calls return the cached path.
  ///
  /// On web: fetches bytes with Cognito auth via FetchService, stores them in
  /// the in-memory LocalImageStorage under key 'ghost_{siteId}_{orientation}',
  /// and returns 'web_img:ghost_{siteId}_{orientation}'. capture_screen reads
  /// these bytes via LocalImageStorage.readBytes() and displays with
  /// Image.memory() — same code path as native; no Image.network() needed.
  ///
  /// ⚠️  ONLINE-ONLY on web ⚠️
  ///
  /// On native, ghost images are cached to disk and available offline.
  /// On web, bytes are in the in-memory store for the duration of the browser
  /// tab. If the app is reloaded, ghost images are re-fetched on next site
  /// load (requires network). Stage 1: store in IndexedDB for offline access.
  static Future<String?> _ensureCachedImage({
    required String remoteUrl,
    required String remoteFileName,
    required String siteId,
    required String orientation,
  }) async {
    // On web: fetch bytes with auth and store in the in-memory image store.
    // Returns a 'web_img:' key so capture_screen can use Image.memory().
    // Requires network on every app launch (no persistent cache in Stage 0).
    if (kIsWeb) {
      try {
        final res =
            _isAppBucketUrl(remoteUrl)
                ? await FetchService.instance.fetch(
                  AppConfig.bucketName,
                  FetchService.s3KeyFromUrl(remoteUrl),
                )
                : await http.get(Uri.parse(remoteUrl));
        if (res.statusCode == 200) {
          final key = 'ghost_${siteId}_$orientation';
          return await LocalImageStorage.saveImage(res.bodyBytes, key);
        }
        dLog(
          'site_service: Ghost image fetch returned ${res.statusCode} for $siteId ($orientation)',
        );
      } catch (e) {
        dLog('site_service: Failed to fetch ghost image on web: $e');
      }
      return null;
    }

    dLog(
      "site_service: Ensuring cached image: $remoteUrl, $remoteFileName, $siteId",
    );
    final docsDir = await getDocsDirPath();
    final ghostsDir = '$docsDir/ghosts/$siteId';
    await ensureDirectory(ghostsDir);

    final localPath = '$ghostsDir/$remoteFileName';

    if (!await fileExistsAsync(localPath)) {
      dLog(
        "site_service: Local file does not exist, fetching image from $remoteUrl",
      );
      int? statusCode;
      try {
        final res =
            _isAppBucketUrl(remoteUrl)
                ? await FetchService.instance.fetch(
                  AppConfig.bucketName,
                  FetchService.s3KeyFromUrl(remoteUrl),
                )
                : await http.get(Uri.parse(remoteUrl));
        statusCode = res.statusCode;
        if (res.statusCode == 200) {
          await writeFileBytes(localPath, res.bodyBytes);
        } else {
          dLog(
            'site_service: Failed to download ghost image from $remoteUrl (HTTP $statusCode)',
          );
          TelemetryService.instance.log(
            TelemetryLevel.warning,
            TelemetryPivot.referenceImageFetchFailed,
            'Ghost image download failed for $siteId ($orientation)',
            context: {
              'siteId': siteId,
              'orientation': orientation,
              'remoteUrl': remoteUrl,
              'statusCode': statusCode,
            },
          );
        }
      } catch (e) {
        dLog('site_service: Error downloading ghost image: $e');
        TelemetryService.instance.log(
          TelemetryLevel.warning,
          TelemetryPivot.referenceImageFetchFailed,
          'Ghost image download error for $siteId ($orientation)',
          error: e,
          context: {
            'siteId': siteId,
            'orientation': orientation,
            'remoteUrl': remoteUrl,
            'statusCode': null,
          },
        );
      }
    } else {
      dLog("site_service: Local file exists, skipping fetch");
    }

    if (!await fileExistsAsync(localPath)) return null;
    return localPath;
  }

  static Future<Set<String>> _loadCachedSiteIds() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString(_kSitesCacheKey);
        if (json == null) return {};
        final data = jsonDecode(json);
        return {for (final s in data['sites'] as List) s['id'] as String};
      }
      final docsDir = await getDocsDirPath();
      final cacheFile = '$docsDir/cache/sites.json';
      if (!await fileExistsAsync(cacheFile)) return {};
      final data = jsonDecode(await readFileString(cacheFile));
      return {for (final s in data['sites'] as List) s['id'] as String};
    } catch (_) {
      return {};
    }
  }

  static void _logSitesChange(List<Site> remoteSites, Set<String> cachedIds) {
    final remoteIds = remoteSites.map((s) => s.id).toSet();
    final newRemoteIds = remoteIds.difference(cachedIds).toList()..sort();
    final localOnlyIds = cachedIds.difference(remoteIds).toList()..sort();
    if (newRemoteIds.isEmpty && localOnlyIds.isEmpty) return;

    dLog(
      'site_service: Sites changed: newRemoteIds: $newRemoteIds, localOnlyIds: $localOnlyIds',
    );

    List<dynamic> truncate(List<String> ids) {
      final preview = ids.take(3).toList();
      return ids.length > 3 ? [...preview, '...'] : preview;
    }

    final level =
        localOnlyIds.isNotEmpty ? TelemetryLevel.warning : TelemetryLevel.info;
    final parts = <String>[];
    if (newRemoteIds.isNotEmpty) parts.add('${newRemoteIds.length} remote-only');
    if (localOnlyIds.isNotEmpty) parts.add('${localOnlyIds.length} local-only');

    TelemetryService.instance.log(
      level,
      TelemetryPivot.sitesUpdated,
      'Site mismatch: ${parts.join(', ')}',
      context: {
        'newSiteIds': truncate(newRemoteIds),
        'localOnlySiteIds': truncate(localOnlyIds),
        'totalRemote': remoteIds.length,
        'totalLocal': cachedIds.length,
      },
    );
  }

  static Future<void> _handleSiteDeletions(
    List<Site> remoteSites,
    Set<String> cachedIds,
  ) async {
    final remoteIds = remoteSites.map((s) => s.id).toSet();
    final deletedIds = cachedIds.difference(remoteIds);
    if (deletedIds.isEmpty) return;
    for (final id in deletedIds) {
      dLog(
        'site_service: Site $id removed from remote — hard-deleting site object, soft-deleting sessions',
      );
      await LocalSiteStorage.deleteLocalSite(id);
      await LocalSessionStorage.softDeleteSessionsForSite(id);
    }
  }

  static Future<void> _cacheSitesJson(String jsonStr) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kSitesCacheKey, jsonStr);
        dLog("Cached sites.json to SharedPreferences");
        return;
      }
      final docsDir = await getDocsDirPath();
      await ensureDirectory('$docsDir/cache');
      await writeFileString('$docsDir/cache/sites.json', jsonStr);
      dLog("Cached sites.json successfully");
    } catch (e) {
      dLog("Failed to cache sites.json: $e");
    }
  }

  static Future<void> _updateCachedSitesWithLocalPaths(
    List<Site> sites,
    String bucketRoot,
  ) async {
    try {
      final updatedData = {
        'bucket_root': bucketRoot,
        'sites': sites.map((site) => site.toJson()).toList(),
      };
      final updatedJsonStr = jsonEncode(updatedData);
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kSitesCacheKey, updatedJsonStr);
        dLog("Updated cached sites.json (SharedPreferences) with local paths");
        return;
      }
      final docsDir = await getDocsDirPath();
      await writeFileString('$docsDir/cache/sites.json', updatedJsonStr);
      dLog("Updated cached sites.json with local paths successfully");
    } catch (e) {
      dLog("Failed to update cached sites.json with local paths: $e");
    }
  }

  static Future<List<Site>> _loadCachedSites() async {
    try {
      String? jsonStr;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonStr = prefs.getString(_kSitesCacheKey);
      } else {
        final docsDir = await getDocsDirPath();
        final cacheFile = '$docsDir/cache/sites.json';
        if (!await fileExistsAsync(cacheFile)) {
          dLog("No cached sites.json found");
          return [];
        }
        jsonStr = await readFileString(cacheFile);
      }

      if (jsonStr == null) return [];
      final data = jsonDecode(jsonStr);

      final List<Site> sites =
          (data['sites'] as List)
              .map((siteJson) => Site.fromJson(siteJson, data['bucket_root']))
              .toList();

      dLog("Loaded ${sites.length} sites from cache");
      return sites;
    } catch (e) {
      dLog("Error loading cached sites: $e");
      return [];
    }
  }

  static List<Site> _mergeSites(List<Site> remoteSites, List<Site> localSites) {
    final mergedSites = <Site>[];
    final seenIds = <String>{};

    for (final site in remoteSites) {
      mergedSites.add(site);
      seenIds.add(site.id);
    }

    for (final site in localSites) {
      if (!seenIds.contains(site.id)) {
        mergedSites.add(site);
        seenIds.add(site.id);
      }
    }

    dLog(
      "Merged sites: ${remoteSites.length} remote + ${localSites.length} local = ${mergedSites.length} total",
    );
    return mergedSites;
  }
}
