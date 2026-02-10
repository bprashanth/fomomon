import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/captured_session.dart';
import '../models/site.dart';
import '../services/local_session_storage.dart';
import '../services/local_site_storage.dart';
import '../services/upload_service.dart';

/// SiteSyncService
/// ---------------
/// Syncs locally created sites (`local_sites.json`) into the remote `sites.json`
/// in S3 after uploads complete. This ensures that newly created sites become
/// part of the canonical sites list and are visible on other devices.
class SiteSyncService {
  /// Main entry point to sync local sites to remote sites.json.
  ///
  /// - Skips in guest mode.
  /// - Never throws to the caller; logs errors instead.
  static Future<void> syncSitesToRemote() async {
    if (AppConfig.isGuestMode) {
      print('site_sync: Skipping sync in guest mode');
      return;
    }

    try {
      final remoteData = await _loadRemoteSitesFromCache();
      final bucketRoot = remoteData.bucketRoot;
      final remoteSites = remoteData.sites;

      final localSites = await LocalSiteStorage.loadLocalSites();
      if (localSites.isEmpty) {
        print('site_sync: No local sites to sync');
        return;
      }

      // Determine which local sites are not yet present remotely.
      final remoteIds = <String>{for (final s in remoteSites) s.id};
      final newLocalSites =
          localSites.where((s) => !remoteIds.contains(s.id)).toList();

      if (newLocalSites.isEmpty) {
        print(
          'site_sync: All local sites already present in remote; nothing to do',
        );
        return;
      }

      // Load sessions to find uploaded ones with image URLs we can use as ghosts.
      final allSessions = await LocalSessionStorage.loadAllSessions();
      final uploadedSessions =
          allSessions.where((s) {
            return s.isUploaded &&
                (s.portraitImageUrl != null &&
                    s.portraitImageUrl!.isNotEmpty) &&
                (s.landscapeImageUrl != null &&
                    s.landscapeImageUrl!.isNotEmpty);
          }).toList();

      if (uploadedSessions.isEmpty) {
        print(
          'site_sync: No uploaded sessions with image URLs found; cannot build ghost images',
        );
        return;
      }

      final newRemoteSites = <Site>[];

      for (final local in newLocalSites) {
        final session = _findFirstUploadedSessionForSite(
          local.id,
          uploadedSessions,
        );
        if (session == null) {
          print(
            'site_sync: No uploaded session found with URLs for local site ${local.id}, skipping',
          );
          continue;
        }

        final portraitRel = _extractRelativePath(
          session.portraitImageUrl!,
          bucketRoot,
        );
        final landscapeRel = _extractRelativePath(
          session.landscapeImageUrl!,
          bucketRoot,
        );

        if (portraitRel == null || landscapeRel == null) {
          print(
            'site_sync: Failed to extract relative paths for site ${local.id}, skipping',
          );
          continue;
        }

        final newSite = Site(
          id: local.id,
          lat: local.lat,
          lng: local.lng,
          referencePortrait: portraitRel,
          referenceLandscape: landscapeRel,
          bucketRoot: bucketRoot,
          surveyQuestions: local.surveyQuestions,
          isLocalSite: false,
        );

        newRemoteSites.add(newSite);
      }

      if (newRemoteSites.isEmpty) {
        print('site_sync: No new remote site entries to add; aborting sync');
        return;
      }

      final allSites = <Site>[...remoteSites, ...newRemoteSites];

      final updatedData = {
        'bucket_root': bucketRoot,
        'sites': allSites.map((s) => s.toJson()).toList(),
      };

      print(
        'site_sync: Uploading updated sites.json with '
        '${remoteSites.length} existing + ${newRemoteSites.length} new sites',
      );

      await UploadService.instance.uploadJson(
        updatedData,
        bucketRoot,
        'sites.json',
      );

      print('site_sync: Successfully synced sites.json to remote');
    } catch (e, st) {
      print('site_sync: Failed to sync sites.json: $e');
      print(st);
    }
  }

  /// Load remote sites and bucket_root from the cached sites.json, or fall back
  /// to an empty list and AppConfig bucketRoot if cache is missing/broken.
  static Future<({String bucketRoot, List<Site> sites})>
  _loadRemoteSitesFromCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/cache');
      final cacheFile = File('${cacheDir.path}/sites.json');

      if (!await cacheFile.exists()) {
        final bucketRoot = AppConfig.getResolvedBucketRoot();
        print(
          'site_sync: No cached remote sites.json found, starting fresh with bucketRoot=$bucketRoot',
        );
        return (bucketRoot: bucketRoot, sites: <Site>[]);
      }

      final jsonStr = await cacheFile.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final bucketRoot =
          (data['bucket_root'] as String?) ?? AppConfig.getResolvedBucketRoot();

      final sites =
          (data['sites'] as List)
              .map(
                (siteJson) =>
                    Site.fromJson(siteJson as Map<String, dynamic>, bucketRoot),
              )
              .toList();

      print(
        'site_sync: Loaded ${sites.length} remote sites from cached sites.json',
      );

      return (bucketRoot: bucketRoot, sites: sites);
    } catch (e) {
      final bucketRoot = AppConfig.getResolvedBucketRoot();
      print(
        'site_sync: Error loading cached remote sites.json ($e), starting with empty list',
      );
      return (bucketRoot: bucketRoot, sites: <Site>[]);
    }
  }

  /// Find the first uploaded session (by timestamp ascending) for a given site.
  static CapturedSession? _findFirstUploadedSessionForSite(
    String siteId,
    List<CapturedSession> sessions,
  ) {
    CapturedSession? candidate;
    for (final s in sessions) {
      if (s.siteId != siteId) continue;
      if (candidate == null || s.timestamp.isBefore(candidate.timestamp)) {
        candidate = s;
      }
    }
    return candidate;
  }

  /// Extract a relative path from a full S3 URL, given the bucketRoot.
  ///
  /// Example:
  ///   fullUrl = https://fomomon.s3.amazonaws.com/t4gc/testing1/foo.jpg
  ///   bucketRoot = https://fomomon.s3.amazonaws.com/t4gc
  ///   -> returns testing1/foo.jpg
  ///
  /// Returns null if extraction fails.
  static String? _extractRelativePath(String fullUrl, String bucketRoot) {
    try {
      final normalizedRoot =
          bucketRoot.endsWith('/')
              ? bucketRoot.substring(0, bucketRoot.length - 1)
              : bucketRoot;

      // Strip query parameters/fragments.
      final uri = Uri.parse(fullUrl);
      final urlWithoutQuery = uri.replace(query: '', fragment: '').toString();

      final idx = urlWithoutQuery.indexOf(normalizedRoot);
      if (idx == -1) {
        print(
          'site_sync: Bucket root $normalizedRoot not found in URL $urlWithoutQuery',
        );
        return null;
      }

      var start = idx + normalizedRoot.length;
      if (start < urlWithoutQuery.length && urlWithoutQuery[start] == '/') {
        start++;
      }
      if (start >= urlWithoutQuery.length) {
        print(
          'site_sync: Computed empty relative path for URL $urlWithoutQuery',
        );
        return null;
      }

      final relative = urlWithoutQuery.substring(start);
      return relative;
    } catch (e) {
      print('site_sync: Failed to extract relative path from $fullUrl: $e');
      return null;
    }
  }
}
