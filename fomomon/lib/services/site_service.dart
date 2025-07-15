/// site_service.dart
/// ----------------
/// Handles loading and parsing `sites.json` from a S3 bucket.
/// Exposes:
/// - fetchSites(bucketRoot): List<Site>

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/site.dart';

class SiteService {
  static Future<List<Site>> fetchSites(String bucketRoot) async {
    final url = '${bucketRoot}sites.json';
    final res = await http.get(Uri.parse(url));

    if (res.statusCode != 200) throw Exception('Failed to load sites');
    final data = jsonDecode(res.body);
    print('data: $data');
    return (data['sites'] as List).map((e) => Site.fromJson(e)).toList();
  }
}
