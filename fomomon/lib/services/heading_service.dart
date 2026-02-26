import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// HeadingService
/// --------------
/// Central place for one-shot compass heading reads.
///
/// Used when:
/// - Saving a completed capture pipeline (confirm/survey screens) so we can
///   persist the heading into `CapturedSession.heading` and later into
///   `Site.referenceHeading` via SiteSyncService (orientation at site).
///
/// Web / PWA notes:
/// - `flutter_compass` does not provide meaningful data on web/PWA; on web we
///   simply return null so the rest of the app continues to work but
///   reference_heading will not be recorded (orientation advisory still works
///   in bearing/distance mode).
class HeadingService {
  static Future<double?> getCurrentHeadingOnce() async {
    if (kIsWeb) {
      return null;
    }

    try {
      final event = await FlutterCompass.events?.first;
      return event?.heading;
    } catch (_) {
      return null;
    }
  }
}

