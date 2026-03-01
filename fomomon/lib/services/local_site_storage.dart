/// Cross-platform local site persistence.
///
/// **Usage**: Import this file at all call sites. The Dart compiler selects
/// the correct backend at compile time via the conditional export below:
///   - Native (Android / iOS): [local_site_storage_native.dart] — uses
///     dart:io File; reads/writes `{docsDir}/local_sites.json`.
///   - Web (Chrome / Safari): [local_site_storage_web.dart] — uses
///     SharedPreferences key `local_sites` (JSON-encoded `{'sites': [...]}`)
///     which maps to localStorage and persists across page reloads.
///
/// **Interface** — all backends expose the same static API:
///
/// ```dart
///   Future<List<Site>> loadLocalSites()
///   Future<void>       saveLocalSite(Site site)
///   Future<void>       deleteLocalSite(String siteId)
/// ```
///
/// **Migration call-map** (old dart:io → this cross-platform API):
///
/// ```dart
///   // BEFORE (native only)
///   final raw = await File('${docsDir}/local_sites.json').readAsString();
///   final sites = (jsonDecode(raw)['sites'] as List).map(Site.fromJson).toList();
///   // AFTER (all platforms)
///   final sites = await LocalSiteStorage.loadLocalSites();
///
///   // BEFORE
///   final data = {'sites': sites.map((s) => s.toJson()).toList()};
///   await File('${docsDir}/local_sites.json').writeAsString(jsonEncode(data));
///   // AFTER
///   await LocalSiteStorage.saveLocalSite(site);
///
///   // BEFORE
///   (remove site from list, re-serialize, write file)
///   // AFTER
///   await LocalSiteStorage.deleteLocalSite(siteId);
/// ```
///
/// **Offline behaviour**:
///   - Native: persisted to disk; survives app restarts.
///   - Web: persisted to localStorage (SharedPreferences); survives page
///     reloads. No additional offline caveats beyond browser storage quotas.
export 'local_site_storage_native.dart'
    if (dart.library.html) 'local_site_storage_web.dart';
