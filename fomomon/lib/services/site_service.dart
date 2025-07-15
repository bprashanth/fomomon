/// site_service.dart
/// ----------------
/// Handles loading and parsing `sites.json` from a S3 bucket.
/// Exposes:
/// - fetchSites(bucketRoot): List<Site>

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/site.dart';
import '../config/app_config.dart';
import 'dart:io';

class SiteService {
  static Future<List<Site>> fetchSites() async {
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

      final json = jsonDecode(jsonStr);
      final List<dynamic> siteList = json['sites'];
      return siteList.map((s) => Site.fromJson(s)).toList();
    } catch (e) {
      print("Failed to fetch sites: $e");
      return [];
    }
  }
}
