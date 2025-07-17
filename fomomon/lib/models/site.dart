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
  });

  factory Site.fromJson(Map<String, dynamic> json, String bucketRoot) {
    return Site(
      id: json['id'],
      lat: json['location']['lat'],
      lng: json['location']['lng'],
      referencePortrait: json['reference_portrait'],
      referenceLandscape: json['reference_landscape'],
      bucketRoot: bucketRoot,
      surveyQuestions:
          (json['survey'] as List<dynamic>)
              .map((q) => SurveyQuestion.fromJson(q))
              .toList(),
    );
  }

  // Site does not have a toJson because we never write to it.
}
