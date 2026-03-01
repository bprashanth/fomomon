/// Web implementation of LocalSiteStorage using shared_preferences.
/// All local sites are stored as a JSON-encoded list under key 'local_sites'.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/site.dart';

class LocalSiteStorage {
  static const String _key = 'local_sites';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<void> saveLocalSite(Site site) async {
    final sites = await loadLocalSites();
    final idx = sites.indexWhere((s) => s.id == site.id);
    if (idx != -1) {
      sites[idx] = site;
    } else {
      sites.add(site);
    }
    await _save(sites);
  }

  static Future<List<Site>> loadLocalSites() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return (data['sites'] as List)
          .map((s) => Site.fromJson(s as Map<String, dynamic>, s['bucket_root'] as String))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> deleteLocalSite(String siteId) async {
    final sites = await loadLocalSites();
    sites.removeWhere((s) => s.id == siteId);
    await _save(sites);
  }

  static Future<void> _save(List<Site> sites) async {
    final prefs = await _prefs;
    final data = {'sites': sites.map((s) => s.toJson()).toList()};
    await prefs.setString(_key, jsonEncode(data));
  }
}
