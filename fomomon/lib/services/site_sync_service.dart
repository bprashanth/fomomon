import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/captured_session.dart';
import '../models/site.dart';
import '../models/telemetry_event.dart';
import '../models/telemetry_pivots.dart';
import '../services/local_session_storage.dart';
import '../services/local_site_storage.dart';
import '../services/telemetry_service.dart';
import '../services/upload_service.dart';
import '../utils/log.dart';

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

      // Determine which local sites are not yet present remotely.
      final remoteIds = <String>{for (final s in remoteSites) s.id};
      final newLocalSites =
          localSites.where((s) => !remoteIds.contains(s.id)).toList();

      if (newLocalSites.isEmpty) {
        dLog(
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
        dLog(
          'site_sync: No uploaded sessions with image URLs found; cannot build ghost images',
        );
        return;
      }

      final newRemoteSites = <Site>[];

      // --- Existing sites (already in sites.json) ---
      // remoteSites = sites loaded from cached sites.json (the canonical list).
      // For each such site we check if this device has any uploaded session for
      // that site ID. If we do, we update that site's reference_heading from
      // the first uploaded session (same "first session" rule as ghost images),
      // then re-upload sites.json so orientation is synced.
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
      // For each we build a Site entry using the first uploaded session for
      // ghost images; reference_heading is set here from that same session.
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
          referenceHeading:
              session
                  .heading, // first uploaded session sets ref heading for new sites
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

      // Write the updated sites.json to local cache so the app immediately
      // reflects the new sites without waiting for a fresh S3 fetch.
      await _writeCacheSitesJson(updatedData);

      // Remove each newly-synced site from local_sites.json. They are now
      // part of the canonical remote sites.json (also in local cache above),
      // so the device will continue to see them. Crucially, if an admin later
      // deletes the site on the server, the next login's fresh fetch will
      // overwrite the local cache and the site will disappear — it won't be
      // re-synced because it no longer exists in local_sites.json.
      for (final site in newRemoteSites) {
        await LocalSiteStorage.deleteLocalSite(site.id);
        dLog(
          'site_sync: Removed ${site.id} from local_sites.json (promoted to remote sites.json)',
        );
        // Sessions are intentionally NOT deleted or soft-deleted here.
        // Soft deletion of sessions only happens when remote sites.json drops a
        // site relative to the local cache (admin delete flow), detected in
        // SiteService._handleSiteDeletions at the next sites.json fetch.
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
        dLog(
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

  /// Write [data] (a sites.json map) to the local cache file so subsequent
  /// calls to [_loadRemoteSitesFromCache] see the updated content immediately.
  /// Mirrors the cache path used by [_loadRemoteSitesFromCache]. Never throws.
  static Future<void> _writeCacheSitesJson(Map<String, dynamic> data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/cache');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final cacheFile = File('${cacheDir.path}/sites.json');
      await cacheFile.writeAsString(jsonEncode(data));
      dLog('site_sync: Updated local cache with synced sites.json');
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
      // Exclude soft-deleted sessions: their S3 image URLs may point to objects
      // that the admin has already deleted alongside the site.
      if (s.isDeleted) continue;
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
      // NOTE: Uri.replace(query: '', fragment: '').toString() would INTRODUCE
      // '?#' on a clean URL (Dart treats '' ≠ null in URI toString).
      // Use string splitting instead.
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

      final relative = urlWithoutQuery.substring(start);
      return relative;
    } catch (e) {
      dLog('site_sync: Failed to extract relative path from $fullUrl: $e');
      return null;
    }
  }
}
