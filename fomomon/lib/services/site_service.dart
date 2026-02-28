/// site_service.dart
/// ----------------
/// Handles loading and parsing `sites.json` from a S3 bucket.
/// Exposes:
/// - fetchSitesAndPrefetchImages(): List<Site>
///
/// The list of sites object returned contains local paths to the reference
/// images.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/site.dart';
import '../models/telemetry_event.dart';
import '../models/telemetry_pivots.dart';
import '../config/app_config.dart';
import '../data/guest_sites.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/local_session_storage.dart';
import '../services/local_site_storage.dart';
import '../services/telemetry_service.dart';
import '../utils/log.dart';
import 'fetch_service.dart';
import 'package:flutter/services.dart';

class SiteService {
  static Future<Directory> _getCacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return cacheDir;
  }

  /// Returns true if [url] points at this app's S3 bucket (same bucket + region as AppConfig).
  /// Used to decide whether to fetch via presigned GET (app bucket) or plain HTTP (e.g. guest bucket).
  ///
  /// Example: true for https://fomomon.s3.ap-south-1.amazonaws.com/t4gc/sites.json
  ///          false for https://fomomonguest.s3.ap-south-1.amazonaws.com/...
  static bool _isAppBucketUrl(String url) {
    final host = Uri.parse(url).host;
    return host ==
            '${AppConfig.bucketName}.s3.${AppConfig.region}.amazonaws.com' ||
        host == '${AppConfig.bucketName}.s3.amazonaws.com';
  }

  static Future<List<Site>> fetchSitesAndPrefetchImages({
    bool async = false,
  }) async {
    // Check if we're in guest mode
    if (AppConfig.isGuestMode) {
      dLog("Guest mode: Loading guest sites");
      final guestSites = await _loadGuestSites();
      final localSites = await LocalSiteStorage.loadLocalSites();
      return _mergeSites(guestSites, localSites);
    }

    // If async mode is enabled, try to return cached data immediately
    if (async) {
      try {
        final cachedSites = await _loadCachedSites();
        final localSites = await LocalSiteStorage.loadLocalSites();
        final mergedSites = _mergeSites(cachedSites, localSites);
        if (cachedSites.isNotEmpty) {
          dLog(
            "Async mode: Returning ${mergedSites.length} sites (${cachedSites.length} remote + ${localSites.length} local) immediately",
          );

          // Start background fetch to update cache (uses bucketName + org/sites.json when root is HTTP)
          _fetchAndCacheSitesInBackground();

          return mergedSites;
        }
      } catch (e) {
        dLog("Async mode: Failed to load cached sites: $e");
      }
    }

    // Synchronous fetch (either async=false or no cached data available)
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

      // Copy asset images to local storage and update local paths
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
    try {
      final dir = await _getCacheDir();
      final guestDir = Directory('${dir.path}/guest_sites');
      if (!await guestDir.exists()) {
        await guestDir.create(recursive: true);
      }

      final filename = '${siteId}_${imageType}.jpg';
      final localPath = '${guestDir.path}/$filename';

      // Load asset as bytes and write to local file
      final byteData = await rootBundle.load(assetPath);
      final file = File(localPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      dLog("Copied asset $assetPath to $localPath");
      return localPath;
    } catch (e) {
      dLog("Error copying asset $assetPath: $e");
      return assetPath; // Return original path if copy fails
    }
  }

  /// Fetches sites.json from remote (presigned GET) or local file according to [AppConfig.getResolvedBucketRoot].
  /// HTTP root → FetchService.fetch(bucketName, "org/sites.json"); file:// root → read local file.
  static Future<List<Site>> _fetchSitesSynchronously() async {
    try {
      final root = AppConfig.getResolvedBucketRoot();
      String jsonStr;

      // Read cached site IDs NOW, before any fetch overwrites the cache.
      // _handleSiteDeletions and _logSitesChange both need the pre-fetch state
      // to detect which sites were removed from the remote.
      final cachedIds = await _loadCachedSiteIds();

      if (root.startsWith("http")) {
        // Presigned GET: bucket + key is equivalent to root + /sites.json (e.g. fomomon + t4gc/sites.json).
        final response = await FetchService.instance.fetch(
          AppConfig.bucketName,
          "${AppConfig.org}/sites.json",
        );
        if (response.statusCode != 200) throw Exception("HTTP error");
        jsonStr = response.body;

        // Cache the successful response
        await _cacheSitesJson(jsonStr);
      } else if (root.startsWith("file://")) {
        final path =
            root.endsWith('/') ? '${root}sites.json' : '$root/sites.json';
        final file = File(Uri.parse(path).toFilePath());
        jsonStr = await file.readAsString();
      } else {
        throw Exception("Unsupported bucketRoot scheme");
      }

      // TODO(prashanth@): use the prefetchImagesInBackground() function here.
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

      // Detect changes and handle deletions against the pre-fetch cache snapshot.
      _logSitesChange(sites, cachedIds);
      await _handleSiteDeletions(sites, cachedIds);

      dLog("Ensuring cached images for ${sites.length} sites");

      for (final site in sites) {
        if (site.referenceLandscape.isEmpty ||
            site.referencePortrait.isEmpty ||
            site.bucketRoot.isEmpty) {
          dLog(
            'Skipping site ${site.id} - missing reference images or bucket root: ${site.bucketRoot}',
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

      // Update the cached sites.json with local paths
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

      // Try to load from cache
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

  /// Fetches sites.json in background via presigned GET when root is HTTP. No-op for file:// (local test).
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

      // Detect changes before overwriting the cache.
      final cachedIds = await _loadCachedSiteIds();

      // Cache the fresh data
      await _cacheSitesJson(response.body);
      dLog("Background fetch: Successfully cached fresh sites data");

      // Log any new sites now that the cache has been refreshed.
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

        // Prefetch both images and set local paths
        final landscapePath = await _ensureCachedImage(
          remoteUrl: landscapeUrl,
          remoteFileName: landscapeFileName,
          siteId: site.id,
          orientation: 'landscape',
        );
        final portraitPath = await _ensureCachedImage(
          remoteUrl: portraitUrl,
          remoteFileName: portraitFileName,
          siteId: site.id,
          orientation: 'portrait',
        );

        // Set the local paths on the site object
        site.localLandscapePath = landscapePath;
        site.localPortraitPath = portraitPath;

        dLog("Background prefetch: Cached images for site ${site.id}");
      }

      // Update the cached sites.json with local paths
      await _updateCachedSitesWithLocalPaths(sites, data['bucket_root']);
      dLog("Background prefetch: Updated cache with local paths");

      dLog("Background prefetch: Completed for all sites");
    } catch (e) {
      dLog("Background prefetch: Failed to prefetch images: $e");
    }
  }

  /// Downloads and caches a ghost reference image, returning the local path on
  /// success or null if the file could not be obtained.
  ///
  /// Returns null (never throws) in two cases:
  ///   1. The download failed (non-200 or network error).
  ///   2. The file is absent from disk even after the attempt.
  /// In both cases a [TelemetryPivot.referenceImageFetchFailed] event is
  /// logged.
  /// Callers must check for null before constructing a FileImage/Image.file -
  /// passing a non-existent path to Image.file() raises PathNotFoundException.
  ///
  /// @param remoteUrl: The full URL of the remote image to fetch.
  /// @param remoteFileName: The filename of the image. This same name is used
  ///   locally to store the image.
  /// @param siteId: The siteID. This is encoded into the storage path for the
  ///   image.
  /// @param orientation: The orientation of the image to fetch. This is only
  ///   used for telemetry.
  static Future<String?> _ensureCachedImage({
    required String remoteUrl,
    required String remoteFileName,
    required String siteId,
    required String orientation,
  }) async {
    dLog(
      "site_service: Ensuring cached image: $remoteUrl, $remoteFileName, $siteId",
    );
    final dir = await getApplicationDocumentsDirectory();
    final ghostsDir = Directory('${dir.path}/ghosts/$siteId');
    if (!await ghostsDir.exists()) await ghostsDir.create(recursive: true);

    final localPath = '${ghostsDir.path}/$remoteFileName';
    final localFile = File(localPath);

    // Only fetch the image if it doesn't exist locally.
    // TODO(prashanth@): check timestamps?
    if (!await localFile.exists()) {
      dLog(
        "site_service: Local file does not exist, fetching image from $remoteUrl",
      );
      int? statusCode;
      try {
        // App bucket uses presigned GET (bucket + s3KeyFromUrl(remoteUrl)); other URLs use plain GET (e.g. fomomonguest).
        // Example: remoteUrl https://fomomon.s3.../t4gc/foo.jpg
        // -> fetch(fomomon, s3KeyFromUrl(remoteUrl) -> t4gc/foo.jpg)
        final res =
            _isAppBucketUrl(remoteUrl)
                ? await FetchService.instance.fetch(
                  AppConfig.bucketName,
                  FetchService.s3KeyFromUrl(remoteUrl),
                )
                : await http.get(Uri.parse(remoteUrl));
        statusCode = res.statusCode;
        if (res.statusCode == 200) {
          await localFile.writeAsBytes(res.bodyBytes);
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

    // Return null if the file doesn't exist — the download either failed or was
    // never attempted. Callers treat null as "no reference image available".
    if (!await localFile.exists()) return null;
    return localPath;
  }

  /// Returns the set of site IDs currently in the local cache, or an empty
  /// set if no cache exists yet. Used to detect remote changes.
  static Future<Set<String>> _loadCachedSiteIds() async {
    try {
      final dir = await _getCacheDir();
      final cacheFile = File('${dir.path}/sites.json');
      if (!await cacheFile.exists()) return {};
      final data = jsonDecode(await cacheFile.readAsString());
      return {for (final s in data['sites'] as List) s['id'] as String};
    } catch (_) {
      return {};
    }
  }

  /// Logs a sitesUpdated event when [remoteSites] and [cachedIds] diverge in
  /// either direction:
  ///   - remote-only: IDs in remote sites.json not present in local cache
  ///   - local-only:  IDs in local cache not present in remote sites.json
  /// Fires as warning when local-only sites exist (remote gap), info otherwise.
  /// ID lists are truncated to 3 entries + '...' if longer.
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
    if (newRemoteIds.isNotEmpty)
      parts.add('${newRemoteIds.length} remote-only');
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

  /// Hard-deletes site objects and soft-deletes sessions for any site that was
  /// in [cachedIds] but is absent from [remoteSites].
  ///
  /// Called whenever a fresh remote sites.json is compared against the local
  /// cache (both synchronous and background fetch paths). The absence of a
  /// site from the remote is treated as an admin deletion.
  ///
  /// Site objects are hard-deleted from local_sites.json (small, safe).
  /// Sessions are soft-deleted (isDeleted flag set) so stale S3 image URLs
  /// from the deleted site cannot be selected as ghost image candidates if
  /// the same site ID is later re-created. Files remain on disk for now.
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
      final dir = await _getCacheDir();
      final cacheFile = File('${dir.path}/sites.json');
      await cacheFile.writeAsString(jsonStr);
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
      final dir = await _getCacheDir();
      final cacheFile = File('${dir.path}/sites.json');

      // Create the updated sites.json structure
      final updatedData = {
        'bucket_root': bucketRoot,
        'sites': sites.map((site) => site.toJson()).toList(),
      };

      final updatedJsonStr = jsonEncode(updatedData);
      await cacheFile.writeAsString(updatedJsonStr);
      dLog("Updated cached sites.json with local paths successfully");
    } catch (e) {
      dLog("Failed to update cached sites.json with local paths: $e");
      // Continue with existing behavior - log error but don't fail
    }
  }

  static Future<List<Site>> _loadCachedSites() async {
    try {
      final dir = await _getCacheDir();
      final cacheFile = File('${dir.path}/sites.json');

      if (!await cacheFile.exists()) {
        dLog("No cached sites.json found");
        return [];
      }

      final jsonStr = await cacheFile.readAsString();
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

  // Helper method to merge remote and local sites, giving precedence to remote sites
  static List<Site> _mergeSites(List<Site> remoteSites, List<Site> localSites) {
    final mergedSites = <Site>[];
    final seenIds = <String>{};

    // Add remote sites first (they get precedence)
    for (final site in remoteSites) {
      mergedSites.add(site);
      seenIds.add(site.id);
    }

    // Add local sites that don't conflict with remote sites
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
