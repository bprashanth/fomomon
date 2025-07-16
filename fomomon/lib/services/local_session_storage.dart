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
    if (await file.exists()) await file.delete();
  }

  static Future<void> markUploaded(String sessionId) async {
    final dir = await _getSessionDir();
    final file = File('${dir.path}/$sessionId.json');
    if (!await file.exists()) return;

    final jsonStr = await file.readAsString();
    final data = jsonDecode(jsonStr);
    data['isUploaded'] = true;
    await file.writeAsString(jsonEncode(data));
  }
}
