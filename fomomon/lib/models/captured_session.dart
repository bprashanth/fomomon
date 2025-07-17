import 'survey_response.dart';

class CapturedSession {
  final String sessionId; // e.g. userId_timestamp
  final String siteId;
  final double latitude;
  final double longitude;
  final String portraitImagePath;
  final String landscapeImagePath;
  final List<SurveyResponse> responses;
  final DateTime timestamp;
  final String userId;
  bool isUploaded;

  CapturedSession({
    required this.sessionId,
    required this.siteId,
    required this.latitude,
    required this.longitude,
    required this.portraitImagePath,
    required this.landscapeImagePath,
    required this.responses,
    required this.timestamp,
    required this.userId,
    this.isUploaded = false,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'siteId': siteId,
    'latitude': latitude,
    'longitude': longitude,
    'portraitImagePath': portraitImagePath,
    'landscapeImagePath': landscapeImagePath,
    'responses': responses.map((r) => r.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
    'isUploaded': isUploaded,
    'userId': userId,
  };

  factory CapturedSession.fromJson(Map<String, dynamic> json) {
    return CapturedSession(
      sessionId: json['sessionId'],
      siteId: json['siteId'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      portraitImagePath: json['portraitImagePath'],
      landscapeImagePath: json['landscapeImagePath'],
      responses:
          (json['responses'] as List)
              .map((r) => SurveyResponse.fromJson(r))
              .toList(),
      timestamp: DateTime.parse(json['timestamp']),
      isUploaded: json['isUploaded'] ?? false,
      userId: json['userId'],
    );
  }
}
