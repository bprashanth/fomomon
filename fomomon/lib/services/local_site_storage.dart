/// local_site_storage.dart
/// ------------------------
/// Handles CRUD operations for locally created sites that are stored on device
/// These sites are created when users are not within range of existing sites

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/site.dart';

class LocalSiteStorage {
  static const String _localSitesFile = 'local_sites.json';

  static Future<void> saveLocalSite(Site site) async {
    final sites = await loadLocalSites();

    // Check if site already exists and update it, otherwise add new
    final existingIndex = sites.indexWhere((s) => s.id == site.id);
    if (existingIndex != -1) {
      sites[existingIndex] = site;
    } else {
      sites.add(site);
    }

    await _saveLocalSites(sites);
    print('Saved local site: ${site.id}');
  }

  static Future<List<Site>> loadLocalSites() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_localSitesFile');

      if (!await file.exists()) {
        print('No local sites file found');
        return [];
      }

      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr);

      final sites =
          (data['sites'] as List)
              .map(
                (siteJson) => Site.fromJson(siteJson, siteJson['bucket_root']),
              )
              .toList();

      print('Loaded ${sites.length} local sites');
      return sites;
    } catch (e) {
      print('Error loading local sites: $e');
      return [];
    }
  }

  static Future<void> _saveLocalSites(List<Site> sites) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_localSitesFile');

      final data = {'sites': sites.map((s) => s.toJson()).toList()};

      await file.writeAsString(jsonEncode(data));
      print('Local sites file updated with ${sites.length} sites');
    } catch (e) {
      print('Error saving local sites: $e');
    }
  }

  static Future<void> deleteLocalSite(String siteId) async {
    final sites = await loadLocalSites();
    sites.removeWhere((site) => site.id == siteId);
    await _saveLocalSites(sites);
    print('Deleted local site: $siteId');
  }
}
