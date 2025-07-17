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
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SiteService {
  static Future<List<Site>> fetchSitesAndPrefetchImages() async {
    final root = AppConfig.getResolvedBucketRoot();
    final path = "$root/sites.json";

    try {
      String jsonStr;

      if (path.startsWith("http")) {
        final response = await http.get(Uri.parse(path));
        if (response.statusCode != 200) throw Exception("HTTP error");
        jsonStr = response.body;
      } else if (path.startsWith("file://")) {
        final file = File(Uri.parse(path).toFilePath());
        jsonStr = await file.readAsString();
      } else {
        throw Exception("Unsupported bucketRoot scheme");
      }

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
          "site_service: Cached images for site ${site.id}, portrait: ${site.localPortraitPath}, landscape: ${site.localLandscapePath}",
        );
      }

      return sites;
    } catch (e) {
      print("Failed to fetch sites: $e");
      return [];
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
}
