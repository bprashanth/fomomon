/// Cross-platform session persistence.
///
/// **Usage**: Import this file at all call sites. The Dart compiler selects
/// the correct backend at compile time via the conditional export below:
///   - Native (Android / iOS): [local_session_storage_native.dart] — uses
///     dart:io File; one JSON file per session in {docsDir}/sessions/.
///   - Web (Chrome / Safari): [local_session_storage_web.dart] — uses
///     SharedPreferences (localStorage); key `session:{id}` per session,
///     plus a `session_ids` list.
///
/// **Interface** — all backends expose the same static API:
///
/// ```dart
///   Future<void>               saveSession(CapturedSession session)
///   Future<List<CapturedSession>> loadAllSessions()
///   Future<void>               deleteSession(String sessionId)
///   Future<void>               softDeleteSessionsForSite(String siteId)
///   Future<void>               markUploadedWithUrls(CapturedSession session)
///   Site                       createSiteForSession(CapturedSession, Site fallbackSite)
/// ```
///
/// **Migration call-map** (old dart:io → this cross-platform API):
///
/// ```dart
///   // BEFORE (native only)
///   await File('${docsDir}/sessions/${id}.json').writeAsString(jsonEncode(data));
///   // AFTER (all platforms)
///   await LocalSessionStorage.saveSession(session);
///
///   // BEFORE
///   final files = Directory('${docsDir}/sessions').listSync();
///   for (final f in files) { final raw = await File(f.path).readAsString(); ... }
///   // AFTER
///   final sessions = await LocalSessionStorage.loadAllSessions();
///
///   // BEFORE
///   await File('${docsDir}/sessions/${id}.json').delete();
///   await File(session.portraitImagePath).delete();   // image cleanup
///   // AFTER
///   await LocalSessionStorage.deleteSession(sessionId);
///   // Note: image cleanup is backend-specific; the web backend is a no-op
///   // (in-memory images are cleared automatically; see local_image_storage).
/// ```
///
/// **Offline behaviour**:
///   - Native: sessions are stored on disk and survive app restarts.
///   - Web: sessions are stored in localStorage (SharedPreferences) and DO
///     persist across page reloads. However, image bytes live in-memory only
///     (see [local_image_storage_web.dart]) — so sessions survive reloads but
///     their image data is gone after a reload unless they were uploaded first.
///     For full offline resilience on web (images + sessions), use the
///     IndexedDB backend (Stage 1). See docs/v2/cross_platform_backends.md.
export 'local_session_storage_native.dart'
    if (dart.library.html) 'local_session_storage_web.dart';
