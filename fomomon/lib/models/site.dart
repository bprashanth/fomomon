/// site.dart
/// ----------
/// Data model representing a field site with lat/lng and reference info
/// Mirrors the structure of entries in `sites.json`

import 'survey_question.dart';

class Site {
  final String id;
  final double lat;
  final double lng;
  final String referencePortrait;
  final String referenceLandscape;
  String? localPortraitPath;
  String? localLandscapePath;
  final String bucketRoot;
  final List<SurveyQuestion> surveyQuestions;
  final bool isLocalSite;

  Site({
    required this.id,
    required this.lat,
    required this.lng,
    required this.referencePortrait,
    required this.referenceLandscape,
    this.localPortraitPath,
    this.localLandscapePath,
    required this.bucketRoot,
    required this.surveyQuestions,
    this.isLocalSite = false,
  });

  factory Site.fromJson(Map<String, dynamic> json, String bucketRoot) {
    return Site(
      id: json['id'],
      // Accept either int or double for lat/lng in JSON
      lat: (json['location']['lat'] as num).toDouble(),
      lng: (json['location']['lng'] as num).toDouble(),
      referencePortrait: json['reference_portrait'],
      referenceLandscape: json['reference_landscape'],
      localPortraitPath: json['local_portrait_path'],
      localLandscapePath: json['local_landscape_path'],
      bucketRoot: bucketRoot,
      surveyQuestions:
          (json['survey'] as List<dynamic>)
              .map((q) => SurveyQuestion.fromJson(q))
              .toList(),
      isLocalSite: json['is_local_site'] ?? false,
    );
  }

  // Factory method for creating local sites
  factory Site.createLocalSite({
    required String id,
    required double lat,
    required double lng,
    required String bucketRoot,
    required List<SurveyQuestion> surveyQuestions,
  }) {
    return Site(
      id: id,
      lat: lat,
      lng: lng,
      referencePortrait: '', // Empty for local sites
      referenceLandscape: '', // Empty for local sites
      bucketRoot: bucketRoot,
      surveyQuestions: surveyQuestions,
      isLocalSite: true,
    );
  }

  // Site does not have a toJson because we never write to it.

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location': {'lat': lat, 'lng': lng},
      'reference_portrait': referencePortrait,
      'reference_landscape': referenceLandscape,
      'local_portrait_path': localPortraitPath,
      'local_landscape_path': localLandscapePath,
      'bucket_root': bucketRoot,
      'survey': surveyQuestions.map((q) => q.toJson()).toList(),
      'is_local_site': isLocalSite,
    };
  }
}
