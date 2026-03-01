/// Web implementation of LocalSessionStorage using shared_preferences.
/// Sessions are stored as JSON strings under keys 'session:{id}'.
/// The list of known IDs is stored under 'session_ids' as a JSON-encoded list.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/captured_session.dart';
import '../models/site.dart';
import '../models/survey_question.dart';
import '../utils/log.dart';

class LocalSessionStorage {
  static const String _idsKey = 'session_ids';
  static String _sessionKey(String id) => 'session:$id';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<void> saveSession(CapturedSession session) async {
    final prefs = await _prefs;
    await prefs.setString(_sessionKey(session.sessionId), jsonEncode(session.toJson()));
    final ids = await _loadIds();
    if (!ids.contains(session.sessionId)) {
      ids.add(session.sessionId);
      await prefs.setString(_idsKey, jsonEncode(ids));
    }
  }

  static Future<List<CapturedSession>> loadAllSessions() async {
    final prefs = await _prefs;
    final ids = await _loadIds();
    final sessions = <CapturedSession>[];
    for (final id in ids) {
      try {
        final jsonStr = prefs.getString(_sessionKey(id));
        if (jsonStr == null) continue;
        sessions.add(CapturedSession.fromJson(jsonDecode(jsonStr)));
      } catch (e) {
        dLog('local_session_storage_web: Error reading session $id: $e');
      }
    }
    return sessions;
  }

  static Future<void> deleteSession(String sessionId) async {
    final prefs = await _prefs;
    // Image deletion is a no-op on web: images are in-memory blobs
    await prefs.remove(_sessionKey(sessionId));
    final ids = await _loadIds();
    ids.remove(sessionId);
    await prefs.setString(_idsKey, jsonEncode(ids));
  }

  static Future<void> softDeleteSessionsForSite(String siteId) async {
    final sessions = await loadAllSessions();
    for (final session in sessions.where((s) => s.siteId == siteId)) {
      session.isDeleted = true;
      await saveSession(session);
      dLog(
        'local_session_storage_web: Soft-deleted session ${session.sessionId} for site $siteId',
      );
    }
  }

  static Future<void> markUploadedWithUrls(CapturedSession session) async {
    session.isUploaded = true;
    final data = session.toJson();
    data['isUploaded'] = true;
    final prefs = await _prefs;
    await prefs.setString(_sessionKey(session.sessionId), jsonEncode(data));
  }

  static Site createSiteForSession(CapturedSession session, Site fallbackSite) {
    final surveyQuestions =
        session.responses
            .map(
              (r) => SurveyQuestion(
                id: r.questionId,
                question: r.questionId,
                type: 'text',
              ),
            )
            .toList();
    return Site.createLocalSite(
      id: session.siteId,
      lat: session.latitude,
      lng: session.longitude,
      surveyQuestions: surveyQuestions,
      bucketRoot: fallbackSite.bucketRoot,
    );
  }

  static Future<List<String>> _loadIds() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_idsKey);
    if (raw == null) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }
}
