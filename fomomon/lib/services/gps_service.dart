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
    // On Android, all top options for accuracy are the same, so we can use
    // high, i.e. best, high and bestForNavigation all map to
    // PRIORITY_HIGH_ACCURACY.
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

  // Get current position once (used for creating new local sites)
  static Future<Position> getCurrentPosition() async {
    if (AppConfig.isTestMode &&
        AppConfig.mockLat != null &&
        AppConfig.mockLng != null) {
      // Return mock position for testing
      return Position(
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
      );
    }

    return await Geolocator.getCurrentPosition();
  }
}
