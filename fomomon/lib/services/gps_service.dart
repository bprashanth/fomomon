/// gps_service.dart
/// ----------------
/// Provides utility functions for:
/// - Requesting and verifying location permissions
/// - Streaming real-time GPS coordinates
/// - Calculating distances between coordinates

import 'package:geolocator/geolocator.dart';
import '../config/app_config.dart';

class GpsService {
  static Future<bool> ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // TODO(prashanth@): getCurrentPosition() should be used to get the current
  // position, this could be more economical than the stream.
  static Stream<Position> getPositionStream() {
    if (AppConfig.isTestMode &&
        AppConfig.mockLat != null &&
        AppConfig.mockLng != null) {
      // Mock a position stream that returns a fixed position every 2 seconds
      return Stream.periodic(
        const Duration(seconds: 2),
        (_) => Position(
          latitude: AppConfig.mockLat!,
          longitude: AppConfig.mockLng!,
          accuracy: 10.0,
          altitude: 0.0,
          altitudeAccuracy: 10.0,
          heading: 0.0,
          headingAccuracy: 10.0,
          speed: 0.0,
          speedAccuracy: 10.0,
          timestamp: DateTime.now(),
        ),
      );
    }
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  static double distanceInMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }
}
