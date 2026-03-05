import 'dart:convert';

import '../config/app_config.dart';
import '../models/captured_session.dart';
import '../models/site.dart';
import '../models/telemetry_event.dart';
import '../models/telemetry_pivots.dart';
import '../services/local_session_storage.dart';
import '../services/local_site_storage.dart';
import '../services/sites_cache_storage.dart';
import '../services/telemetry_service.dart';
import '../services/upload_service.dart';
import '../utils/log.dart';

// Shared cache key used by both this service and site_service. Both services
// read/write the same slot so syncSitesToRemote always starts from the full
// current remote state (written by site_service at login time) rather than an
// empty list. On native the key is ignored — all cache reads/writes go to the
// same file regardless of key.
const String _kSyncCacheKey = 'sites_cache';

/// SiteSyncService
/// ---------------
/// Syncs locally created sites (`local_sites.json`) into the remote `sites.json`
/// in S3 after uploads complete. This ensures that newly created sites become
/// part of the canonical sites list and are visible on other devices.
/// Also updates reference_heading on sites (existing and new) from the first
/// uploaded session per site, so orientation is synced back to sites.json.
class SiteSyncService {
  /// Main entry point to sync local sites to remote sites.json.
  ///
  /// - Skips in guest mode.
  /// - Never throws to the caller; logs errors instead.
  static Future<void> syncSitesToRemote() async {
    if (AppConfig.isGuestMode) {
      dLog('site_sync: Skipping sync in guest mode');
      return;
    }

    try {
      final remoteData = await _loadRemoteSitesFromCache();
      final bucketRoot = remoteData.bucketRoot;
      final remoteSites = remoteData.sites;

      final localSites = await LocalSiteStorage.loadLocalSites();
      if (localSites.isEmpty) {
        dLog('site_sync: No local sites to sync');
        return;
      }

      final remoteIds = <String>{for (final s in remoteSites) s.id};
      final newLocalSites =
          localSites.where((s) => !remoteIds.contains(s.id)).toList();

      if (newLocalSites.isEmpty) {
        dLog(
          'site_sync: All local sites already present in remote; nothing to do',
        );
        return;
      }

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
        dLog(
          'site_sync: No uploaded sessions with image URLs found; cannot build ghost images',
        );
        return;
      }

      final newRemoteSites = <Site>[];

      // --- Existing sites (already in sites.json) ---
      final updatedRemoteSites = <Site>[];
      for (final remote in remoteSites) {
        final session = _findFirstUploadedSessionForSite(
          remote.id,
          uploadedSessions,
        );
        if (session != null && session.heading != null) {
          updatedRemoteSites.add(
            Site(
              id: remote.id,
              lat: remote.lat,
              lng: remote.lng,
              referencePortrait: remote.referencePortrait,
              referenceLandscape: remote.referenceLandscape,
              referenceHeading: session.heading,
              bucketRoot: remote.bucketRoot,
              surveyQuestions: remote.surveyQuestions,
              isLocalSite: remote.isLocalSite,
            ),
          );
        } else {
          updatedRemoteSites.add(remote);
        }
      }

      // --- New local sites (added on this phone, not yet in sites.json) ---
      for (final local in newLocalSites) {
        final session = _findFirstUploadedSessionForSite(
          local.id,
          uploadedSessions,
        );
        if (session == null) {
          dLog(
            'site_sync: No uploaded session found with URLs for local site ${local.id}, skipping',
          );
          continue;
        }

        dLog(
          'site_sync: Extracting relative paths for site ${local.id}: portrait: ${session.portraitImageUrl}, landscape: ${session.landscapeImageUrl}',
        );
        final portraitRel = _extractRelativePath(
          session.portraitImageUrl!,
          bucketRoot,
        );
        final landscapeRel = _extractRelativePath(
          session.landscapeImageUrl!,
          bucketRoot,
        );

        if (portraitRel == null || landscapeRel == null) {
          dLog(
            'site_sync: Failed to extract relative paths for site ${local.id}, skipping',
          );
          continue;
        }

        dLog(
          'site_sync: Extracted relative paths for site ${local.id}: portrait: $portraitRel, landscape: $landscapeRel',
        );

        final newSite = Site(
          id: local.id,
          lat: local.lat,
          lng: local.lng,
          referencePortrait: portraitRel,
          referenceLandscape: landscapeRel,
          referenceHeading: session.heading,
          bucketRoot: bucketRoot,
          surveyQuestions: local.surveyQuestions,
          isLocalSite: false,
        );

        newRemoteSites.add(newSite);
        TelemetryService.instance.log(
          TelemetryLevel.info,
          TelemetryPivot.siteSynced,
          'New site written to sites.json: ${local.id}',
          context: {'siteId': local.id},
        );
      }

      if (newRemoteSites.isEmpty) {
        dLog('site_sync: No new remote site entries to add; aborting sync');
        return;
      }

      final allSites = <Site>[...updatedRemoteSites, ...newRemoteSites];

      final updatedData = {
        'bucket_root': bucketRoot,
        'sites': allSites.map((s) => s.toJson()).toList(),
      };

      dLog(
        'site_sync: Uploading updated sites.json with '
        '${remoteSites.length} existing + ${newRemoteSites.length} new sites',
      );

      await UploadService.instance.uploadJson(
        updatedData,
        bucketRoot,
        'sites.json',
      );

      dLog('site_sync: Successfully synced sites.json to remote');

      await _writeCacheSitesJson(updatedData);

      for (final site in newRemoteSites) {
        await LocalSiteStorage.deleteLocalSite(site.id);
        dLog(
          'site_sync: Removed ${site.id} from local_sites.json (promoted to remote sites.json)',
        );
      }
    } catch (e, st) {
      dLog('site_sync: Failed to sync sites.json: $e');
      dLog(st.toString());
      TelemetryService.instance.log(
        TelemetryLevel.error,
        TelemetryPivot.siteSyncFailed,
        'syncSitesToRemote() failed',
        error: e,
      );
    }
  }

  /// Load remote sites and bucket_root from the cached sites.json.
  ///
  /// Reads [_kSyncCacheKey], which is shared with site_service. On first launch
  /// site_service writes this key at login time, so syncSitesToRemote always
  /// starts from the full current remote state rather than an empty list.
  static Future<({String bucketRoot, List<Site> sites})>
  _loadRemoteSitesFromCache() async {
    try {
      final jsonStr = await SitesCacheStorage.read(_kSyncCacheKey);
      if (jsonStr == null) {
        final bucketRoot = AppConfig.getResolvedBucketRoot();
        dLog(
          'site_sync: No cached remote sites.json found, starting fresh with bucketRoot=$bucketRoot',
        );
        return (bucketRoot: bucketRoot, sites: <Site>[]);
      }

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

      dLog(
        'site_sync: Loaded ${sites.length} remote sites from cached sites.json',
      );

      return (bucketRoot: bucketRoot, sites: sites);
    } catch (e) {
      final bucketRoot = AppConfig.getResolvedBucketRoot();
      dLog(
        'site_sync: Error loading cached remote sites.json ($e), starting with empty list',
      );
      return (bucketRoot: bucketRoot, sites: <Site>[]);
    }
  }

  /// Write [data] to the local cache so subsequent calls to
  /// [_loadRemoteSitesFromCache] see the updated content immediately.
  static Future<void> _writeCacheSitesJson(Map<String, dynamic> data) async {
    try {
      await SitesCacheStorage.write(_kSyncCacheKey, jsonEncode(data));
      dLog('site_sync: Updated cache with synced sites.json');
    } catch (e) {
      dLog('site_sync: Failed to update local cache after sync: $e');
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
      if (s.isDeleted) continue;
      if (candidate == null || s.timestamp.isBefore(candidate.timestamp)) {
        candidate = s;
      }
    }
    return candidate;
  }

  /// Extract a relative path from a full S3 URL, given the bucketRoot.
  static String? _extractRelativePath(String fullUrl, String bucketRoot) {
    try {
      final normalizedRoot =
          bucketRoot.endsWith('/')
              ? bucketRoot.substring(0, bucketRoot.length - 1)
              : bucketRoot;

      final urlWithoutQuery = fullUrl.split('#').first.split('?').first;

      final idx = urlWithoutQuery.indexOf(normalizedRoot);
      if (idx == -1) {
        dLog(
          'site_sync: Bucket root $normalizedRoot not found in URL $urlWithoutQuery',
        );
        return null;
      }

      var start = idx + normalizedRoot.length;
      if (start < urlWithoutQuery.length && urlWithoutQuery[start] == '/') {
        start++;
      }
      if (start >= urlWithoutQuery.length) {
        dLog(
          'site_sync: Computed empty relative path for URL $urlWithoutQuery',
        );
        return null;
      }

      return urlWithoutQuery.substring(start);
    } catch (e) {
      dLog('site_sync: Failed to extract relative path from $fullUrl: $e');
      return null;
    }
  }
}
