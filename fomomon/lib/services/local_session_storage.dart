/// This class manages CRUD operations on sessions - store, read, delete.
/// It assumes single writer on a single session.
///
/// Examples:
///
/// final session = CapturedSession(
///   sessionId: 'user123_20250715T105000',
///   siteId: 'test_site_001',
///   latitude: 12.9719,
///   longitude: 77.5937,
///   portraitImagePath: '/path/to/portrait.jpg',
///   landscapeImagePath: '/path/to/landscape.jpg',
///   responses: [SurveyResponse(questionId: 'q1', answer: 'Deer')],
///   timestamp: DateTime.now(),
/// );
///
/// await LocalSessionStorage.saveSession(session);
///
/// Writing:
///   getSession() -> CapturedSession?
///   Modify session object
///   saveSession(CapturedSession)
///
/// Filtering:
///   loadAllSessions() -> List<CapturedSession>
///   Search for keys
///
/// Deleting:
///   for session in loadAllSessions():
///     deleteSession(String sessionId)

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/captured_session.dart';
import '../models/site.dart';
import '../models/survey_question.dart';

class LocalSessionStorage {
  static Future<Directory> _getSessionDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final sessionDir = Directory('${dir.path}/sessions');
    if (!await sessionDir.exists()) await sessionDir.create(recursive: true);
    return sessionDir;
  }

  static Future<void> saveSession(CapturedSession session) async {
    final dir = await _getSessionDir();
    final file = File('${dir.path}/${session.sessionId}.json');
    final jsonStr = jsonEncode(session.toJson());
    await file.writeAsString(jsonStr);
  }

  static Future<List<CapturedSession>> loadAllSessions() async {
    final dir = await _getSessionDir();
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    );

    final sessions = <CapturedSession>[];
    for (final file in files) {
      try {
        final jsonStr = await file.readAsString();
        final data = jsonDecode(jsonStr);
        sessions.add(CapturedSession.fromJson(data));
      } catch (e) {
        print('Error reading session file ${file.path}: $e');
      }
    }
    return sessions;
  }

  static Future<void> deleteSession(String sessionId) async {
    final dir = await _getSessionDir();
    final file = File('${dir.path}/$sessionId.json');

    // Load session first to get image paths
    CapturedSession? session;
    if (await file.exists()) {
      try {
        final jsonStr = await file.readAsString();
        final data = jsonDecode(jsonStr);
        session = CapturedSession.fromJson(data);
      } catch (e) {
        print('Error loading session for deletion ${file.path}: $e');
      }
    }

    // Delete portrait image if it exists
    if (session != null && session.portraitImagePath.isNotEmpty) {
      try {
        final portraitFile = File(session.portraitImagePath);
        if (await portraitFile.exists()) {
          await portraitFile.delete();
        }
      } catch (e) {
        print('Error deleting portrait image ${session.portraitImagePath}: $e');
      }
    }

    // Delete landscape image if it exists
    if (session != null && session.landscapeImagePath.isNotEmpty) {
      try {
        final landscapeFile = File(session.landscapeImagePath);
        if (await landscapeFile.exists()) {
          await landscapeFile.delete();
        }
      } catch (e) {
        print(
          'Error deleting landscape image ${session.landscapeImagePath}: $e',
        );
      }
    }

    // Delete JSON file
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Mark a session as uploaded and persist its full state, including
  /// portrait/landscape image URLs.
  /// Why is this important? 1. Consistency 2. SiteSyncService needs the URLs
  /// to create ghost images for new sites, and this level of consistency means
  /// we can just check the persisted site object for the URLs.
  /// NB: These are raw unsigned urls, the presigned urls are only used
  /// transiently during uploads.
  static Future<void> markUploadedWithUrls(CapturedSession session) async {
    final dir = await _getSessionDir();
    final file = File('${dir.path}/${session.sessionId}.json');

    // Ensure flag is set on the in-memory object as well.
    session.isUploaded = true;

    final data = session.toJson();
    data['isUploaded'] = true;

    await file.writeAsString(jsonEncode(data));
  }

  // Creates a Site from a Session. While this is backwards, we use this method
  // to upload stale sessions from a user's phone after the sites have all
  // changed. The main point is to not discard the data.
  static Site createSiteForSession(CapturedSession session, Site fallbackSite) {
    // Convert session responses to survey questions
    final surveyQuestions =
        session.responses
            .map(
              (response) => SurveyQuestion(
                id: response.questionId,
                // Use questionId as question text as fallback
                question: response.questionId,
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
}
