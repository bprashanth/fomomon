/// site.dart
/// ----------
/// Data model representing a field site with lat/lng and reference info
/// Mirrors the structure of entries in `sites.json`

class Site {
  final String id;
  final double lat;
  final double lng;

  Site({required this.id, required this.lat, required this.lng});

  factory Site.fromJson(Map<String, dynamic> json) {
    return Site(
      id: json['id'],
      lat: json['location']['lat'],
      lng: json['location']['lng'],
    );
  }
}
