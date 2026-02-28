/// telemetry_service.dart
/// ----------------------
/// Lightweight offline-buffered telemetry. Events are queued locally and
/// flushed to S3 once per upload session (piggybacked on UploadService).
///
/// Usage:
///   TelemetryService.instance.log(TelemetryLevel.error, TelemetryPivot.loginFailed, 'Login failed', error: e);
///   await TelemetryService.instance.flush(userId, org, platform);
///
/// See docs/observability.md for architecture, schema, and S3 path details.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/telemetry_event.dart';
import '../services/auth_service.dart';
import '../services/s3_signer_service.dart';
import '../services/telemetry_storage.dart';

class TelemetryService {
  TelemetryService._privateConstructor();
  static final TelemetryService instance =
      TelemetryService._privateConstructor();

  /// Buffer one telemetry event. No-ops immediately if telemetry is disabled.
  void log(
    TelemetryLevel level,
    String pivot,
    String message, {
    Object? error,
    Map<String, dynamic>? context,
  }) {
    if (!AppConfig.isTelemetryEnabled) return;

    final event = TelemetryEvent(
      timestamp: DateTime.now().toUtc(),
      level: level,
      pivot: pivot,
      message: message,
      error: error?.toString(),
      context: context,
    );

    // Fire-and-forget; errors are swallowed inside appendEvent.
    TelemetryStorage.appendEvent(event.toJson());
  }

  /// Drain the buffer and PUT a single JSON file to S3.
  /// Call this at the end of UploadService.uploadAllSessions().
  ///
  /// S3 key: {org}/telemetry/{YYYY-MM-DD}/{userId}_{epochMs}.json
  Future<void> flush(String userId, String org, String platform) async {
    if (!AppConfig.isTelemetryEnabled) return;

    try {
      final events = await TelemetryStorage.loadAndClear();
      if (events.isEmpty) return;

      final now = DateTime.now().toUtc();
      final date =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final epochMs = now.millisecondsSinceEpoch;

      final s3Key = AppConfig.telemetryS3Key(org, date, userId, epochMs);

      final payload = {
        'appVersion': AppConfig.appVersion,
        'platform': platform,
        'userId': userId,
        'org': org,
        'flushedAt': now.toIso8601String(),
        'events': events,
      };

      final credentials = await AuthService.instance.getUploadCredentials();
      final presignedUrl =
          await S3SignerService.instance.createPresignedJsonPutUrl(
        bucketName: AppConfig.bucketName,
        s3Key: s3Key,
        credentials: credentials,
      );

      final body = utf8.encode(jsonEncode(payload));
      final response = await http.put(
        Uri.parse(presignedUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200) {
        // On failure, re-buffer the events so they are not lost.
        for (final e in events) {
          await TelemetryStorage.appendEvent(e);
        }
      }
    } catch (_) {
      // Telemetry flush must never crash the app.
    }
  }

  /// Convenience: detect platform string from kIsWeb.
  static String get currentPlatform => kIsWeb ? 'web' : 'android';
}
