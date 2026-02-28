import 'survey_response.dart';

class CapturedSession {
  final String sessionId; // e.g. userId_timestamp
  final String siteId;
  final double latitude;
  final double longitude;
  final double? heading;
  final String portraitImagePath;
  final String landscapeImagePath;
  final List<SurveyResponse> responses;
  final DateTime timestamp;
  final String userId;
  String? portraitImageUrl;
  String? landscapeImageUrl;
  bool isUploaded;
  // Soft-delete flag. Set when the remote sites.json no longer contains this
  // session's site, indicating the admin deleted the site server-side.
  // Soft-deleted sessions are excluded from ghost image candidate selection
  // (SiteSyncService._findFirstUploadedSessionForSite). They are NOT hard-
  // deleted from disk; a future cleanup pass can do that.
  bool isDeleted;

  CapturedSession({
    required this.sessionId,
    required this.siteId,
    required this.latitude,
    required this.longitude,
    this.heading,
    required this.portraitImagePath,
    required this.landscapeImagePath,
    required this.responses,
    required this.timestamp,
    required this.userId,
    this.portraitImageUrl = '',
    this.landscapeImageUrl = '',
    this.isUploaded = false,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'siteId': siteId,
    'latitude': latitude,
    'longitude': longitude,
    'heading': heading,
    'portraitImagePath': portraitImagePath,
    'landscapeImagePath': landscapeImagePath,
    'portraitImageUrl': portraitImageUrl,
    'landscapeImageUrl': landscapeImageUrl,
    'responses': responses.map((r) => r.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
    'isUploaded': isUploaded,
    'isDeleted': isDeleted,
    'userId': userId,
  };

  factory CapturedSession.fromJson(Map<String, dynamic> json) {
    return CapturedSession(
      sessionId: json['sessionId'],
      siteId: json['siteId'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      heading:
          json['heading'] != null
              ? (json['heading'] as num).toDouble()
              : null,
      portraitImagePath: json['portraitImagePath'],
      landscapeImagePath: json['landscapeImagePath'],
      portraitImageUrl: json['portraitImageUrl'] ?? '',
      landscapeImageUrl: json['landscapeImageUrl'] ?? '',
      responses:
          (json['responses'] as List)
              .map((r) => SurveyResponse.fromJson(r))
              .toList(),
      timestamp: DateTime.parse(json['timestamp']),
      isUploaded: json['isUploaded'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      userId: json['userId'],
    );
  }
}
