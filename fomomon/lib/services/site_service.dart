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
import '../config/app_config.dart';
import '../data/guest_sites.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/local_site_storage.dart';
import 'package:flutter/services.dart';

class SiteService {
  static Future<Directory> _getCacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return cacheDir;
  }

  static Future<List<Site>> fetchSitesAndPrefetchImages({
    bool async = false,
  }) async {
    // Check if we're in guest mode
    if (AppConfig.isGuestMode) {
      print("Guest mode: Loading guest sites");
      final guestSites = await _loadGuestSites();
      final localSites = await LocalSiteStorage.loadLocalSites();
      return _mergeSites(guestSites, localSites);
    }

    final root = AppConfig.getResolvedBucketRoot();
    final path = "$root/sites.json";

    // If async mode is enabled, try to return cached data immediately
    if (async) {
      try {
        final cachedSites = await _loadCachedSites();
        final localSites = await LocalSiteStorage.loadLocalSites();
        final mergedSites = _mergeSites(cachedSites, localSites);
        if (cachedSites.isNotEmpty) {
          print(
            "Async mode: Returning ${mergedSites.length} sites (${cachedSites.length} remote + ${localSites.length} local) immediately",
          );

          // Start background fetch to update cache
          _fetchAndCacheSitesInBackground(path);

          return mergedSites;
        }
      } catch (e) {
        print("Async mode: Failed to load cached sites: $e");
      }
    }

    // Synchronous fetch (either async=false or no cached data available)
    final remoteSites = await _fetchSitesSynchronously(path);
    final localSites = await LocalSiteStorage.loadLocalSites();
    return _mergeSites(remoteSites, localSites);
  }

  static Future<List<Site>> _loadGuestSites() async {
    try {
      final data = jsonDecode(GuestSites.guestSitesJson);
      print("Loaded guest sites: $data");
      final List<Site> sites =
          (data['sites'] as List)
              .map((siteJson) => Site.fromJson(siteJson, data['bucket_root']))
              .toList();

      if (sites.isEmpty) {
        print('No guest sites found');
        return [];
      }

      print(
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

      print("Loaded ${sites.length} guest sites with local paths");
      return sites;
    } catch (e) {
      print("Error loading guest sites: $e");
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

      print("Copied asset $assetPath to $localPath");
      return localPath;
    } catch (e) {
      print("Error copying asset $assetPath: $e");
      return assetPath; // Return original path if copy fails
    }
  }

  static Future<List<Site>> _fetchSitesSynchronously(String path) async {
    try {
      String jsonStr;

      if (path.startsWith("http")) {
        final response = await http.get(Uri.parse(path));
        if (response.statusCode != 200) throw Exception("HTTP error");
        jsonStr = response.body;

        // Cache the successful response
        await _cacheSitesJson(jsonStr);
      } else if (path.startsWith("file://")) {
        final file = File(Uri.parse(path).toFilePath());
        jsonStr = await file.readAsString();
      } else {
        throw Exception("Unsupported bucketRoot scheme");
      }

      // TODO(prashanth@): use the prefetchImagesInBackground() function here.
      final data = jsonDecode(jsonStr);
      print("Fetched sites: $data");
      final List<Site> sites =
          (data['sites'] as List)
              .map((siteJson) => Site.fromJson(siteJson, data['bucket_root']))
              .toList();

      if (sites.isEmpty) {
        print('No sites found in sites.json');
        return [];
      }

      print("Ensuring cached images for ${sites.length} sites");

      for (final site in sites) {
        if (site.referenceLandscape.isEmpty ||
            site.referencePortrait.isEmpty ||
            site.bucketRoot.isEmpty) {
          print(
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
        );

        site.localLandscapePath = await _ensureCachedImage(
          remoteUrl: landscapeUrl,
          remoteFileName: landscapeFileName,
          siteId: site.id,
        );

        print(
          "[site_service]: Cached images for site ${site.id}, portrait: ${site.localPortraitPath}, landscape: ${site.localLandscapePath}",
        );
      }

      // Update the cached sites.json with local paths
      await _updateCachedSitesWithLocalPaths(sites, data['bucket_root']);

      return sites;
    } catch (e) {
      print("Failed to fetch sites from network: $e");
      print("Attempting to load cached sites.json");

      // Try to load from cache
      try {
        final cachedSites = await _loadCachedSites();
        if (cachedSites.isNotEmpty) {
          print("Successfully loaded ${cachedSites.length} sites from cache");
          return cachedSites;
        }
      } catch (cacheError) {
        print("Failed to load cached sites: $cacheError");
      }

      print("No cached sites available, returning empty list");
      return [];
    }
  }

  static Future<void> _fetchAndCacheSitesInBackground(String path) async {
    try {
      print("Background fetch: Starting to fetch fresh sites data");

      if (!path.startsWith("http")) {
        print("Background fetch: Skipping non-HTTP path");
        return;
      }

      final response = await http.get(Uri.parse(path));
      if (response.statusCode != 200) {
        print("Background fetch: HTTP error ${response.statusCode}");
        return;
      }

      // Cache the fresh data
      await _cacheSitesJson(response.body);
      print("Background fetch: Successfully cached fresh sites data");

      _prefetchImagesInBackground(response.body);
    } catch (e) {
      print("Background fetch: Failed to fetch fresh sites data: $e");
    }
  }

  static Future<void> _prefetchImagesInBackground(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr);
      final List<Site> sites =
          (data['sites'] as List)
              .map((siteJson) => Site.fromJson(siteJson, data['bucket_root']))
              .toList();

      print(
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
        );
        final portraitPath = await _ensureCachedImage(
          remoteUrl: portraitUrl,
          remoteFileName: portraitFileName,
          siteId: site.id,
        );

        // Set the local paths on the site object
        site.localLandscapePath = landscapePath;
        site.localPortraitPath = portraitPath;

        print("Background prefetch: Cached images for site ${site.id}");
      }

      // Update the cached sites.json with local paths
      await _updateCachedSitesWithLocalPaths(sites, data['bucket_root']);
      print("Background prefetch: Updated cache with local paths");

      print("Background prefetch: Completed for all sites");
    } catch (e) {
      print("Background prefetch: Failed to prefetch images: $e");
    }
  }

  static Future<String> _ensureCachedImage({
    required String remoteUrl,
    required String remoteFileName,
    required String siteId,
  }) async {
    print(
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
      print(
        "site_service: Local file does not exist, fetching image from $remoteUrl",
      );
      try {
        final res = await http.get(Uri.parse(remoteUrl));
        if (res.statusCode == 200) {
          await localFile.writeAsBytes(res.bodyBytes);
        } else {
          print('site_service: Failed to download ghost image from $remoteUrl');
        }
      } catch (e) {
        print('site_service: Error downloading ghost image: $e');
      }
    } else {
      print("site_service: Local file exists, skipping fetch");
    }
    return localPath;
  }

  static Future<void> _cacheSitesJson(String jsonStr) async {
    try {
      final dir = await _getCacheDir();
      final cacheFile = File('${dir.path}/sites.json');
      await cacheFile.writeAsString(jsonStr);
      print("Cached sites.json successfully");
    } catch (e) {
      print("Failed to cache sites.json: $e");
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
      print("Updated cached sites.json with local paths successfully");
    } catch (e) {
      print("Failed to update cached sites.json with local paths: $e");
      // Continue with existing behavior - log error but don't fail
    }
  }

  static Future<List<Site>> _loadCachedSites() async {
    try {
      final dir = await _getCacheDir();
      final cacheFile = File('${dir.path}/sites.json');

      if (!await cacheFile.exists()) {
        print("No cached sites.json found");
        return [];
      }

      final jsonStr = await cacheFile.readAsString();
      final data = jsonDecode(jsonStr);

      final List<Site> sites =
          (data['sites'] as List)
              .map((siteJson) => Site.fromJson(siteJson, data['bucket_root']))
              .toList();

      print("Loaded ${sites.length} sites from cache");
      return sites;
    } catch (e) {
      print("Error loading cached sites: $e");
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

    print(
      "Merged sites: ${remoteSites.length} remote + ${localSites.length} local = ${mergedSites.length} total",
    );
    return mergedSites;
  }
}
