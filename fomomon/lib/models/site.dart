/// site.dart
/// ----------
/// Data model representing a field site with lat/lng and reference info
/// Mirrors the structure of entries in `sites.json`

class Site {
  final String id;
  final double lat;
  final double lng;
  final String referencePortrait;
  final String referenceLandscape;
  String? localPortraitPath;
  String? localLandscapePath;
  final String bucketRoot;

  Site({
    required this.id,
    required this.lat,
    required this.lng,
    required this.referencePortrait,
    required this.referenceLandscape,
    this.localPortraitPath,
    this.localLandscapePath,
    required this.bucketRoot,
  });

  factory Site.fromJson(Map<String, dynamic> json, String bucketRoot) {
    return Site(
      id: json['id'],
      lat: json['location']['lat'],
      lng: json['location']['lng'],
      referencePortrait: json['reference_portrait'],
      referenceLandscape: json['reference_landscape'],
      bucketRoot: bucketRoot,
    );
  }
}
