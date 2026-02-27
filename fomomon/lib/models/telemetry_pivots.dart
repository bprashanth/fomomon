/// telemetry_pivots.dart
/// ---------------------
/// Canonical pivot point names for TelemetryService.log().
///
/// Naming rules:
///   Errors   → {domain}_{action}_failed   (e.g. login_failed)
///   Warnings → descriptive phrase          (e.g. gps_permission_denied)
///   Info     → past tense                  (e.g. session_uploaded)
///
/// Ordered by app lifecycle — auth → site load → GPS → capture → upload → sync.
/// Every TelemetryService.log() call site MUST use one of these constants;
/// never pass an inline string.
///
/// See docs/observability.md for the full pivot reference table and schema.
class TelemetryPivot {
  TelemetryPivot._();

  // - 1. Auth / Login -
  // These happen first: the app fetches auth_config.json from S3 before the
  // user can log in.

  /// fetchAuthConfig() failed (network, HTTP error, or JSON parse failure).
  /// App cannot proceed to login without this config.
  /// Logged from: login_screen.dart
  static const String authConfigFetchFailed = 'auth_config_fetch_failed';

  /// login() failed after the user submitted credentials.
  /// Covers: wrong password, unknown user, network error, Cognito service error.
  /// Logged from: login_screen.dart
  static const String loginFailed = 'login_failed';

  // - 2. Site loading (immediately after login) -
  // The app fetches sites.json from S3 to know which monitoring sites exist.

  /// sites.json could not be fetched from S3 (network down, HTTP error, etc.).
  /// If a local cache exists the app falls back silently; see siteFetchCacheFallback.
  /// Logged from: site_service.dart
  static const String siteFetchFailed = 'site_fetch_failed';

  /// The S3 fetch for sites.json failed but a cached copy was used instead.
  /// Indicates the device was offline at startup; data may be stale.
  /// Logged from: site_service.dart
  static const String siteFetchCacheFallback = 'site_fetch_cache_fallback';

  // - 3. GPS (during field work) -
  // Permission must be granted before the map and proximity trigger work.

  /// Location service is disabled on the device, or the user denied the
  /// permission prompt. GPS-dependent features will be unavailable.
  /// Logged from: gps_service.dart
  static const String gpsPermissionDenied = 'gps_permission_denied';

  // - 4. Session capture (end of capture pipeline) -
  // A capture pipeline run = photos + survey answers saved as a local session.

  /// Session JSON saved to local storage at the end of the capture pipeline.
  /// This is the last step before the session enters the upload queue.
  /// Logged from: survey_screen.dart
  static const String sessionCaptured = 'session_captured';

  // - 5. Upload flow -
  // Uploads are triggered manually by the user via the upload dial widget.

  /// The Cognito refresh token could not be renewed before or during upload.
  /// The user must log in again before the next upload attempt.
  /// Logged from: upload_service.dart (when AuthSessionExpiredException surfaces)
  static const String tokenRefreshFailed = 'token_refresh_failed';

  /// A single session (images + JSON) failed to upload to S3.
  /// The session remains in the local queue and will be retried next time.
  /// Logged from: upload_service.dart
  static const String sessionUploadFailed = 'session_upload_failed';

  /// A single session was successfully uploaded to S3.
  /// Logged from: upload_service.dart
  static const String sessionUploaded = 'session_uploaded';

  // - 6. Site sync (after all sessions are uploaded) -
  // After uploads, locally created sites are merged into the remote sites.json.

  /// syncSitesToRemote() could not write the updated sites.json to S3.
  /// Locally created sites will not appear on other devices until resolved.
  /// Logged from: site_sync_service.dart
  static const String siteSyncFailed = 'site_sync_failed';

  /// A locally created site was successfully written into the remote sites.json.
  /// Logged from: site_sync_service.dart
  static const String siteSynced = 'site_synced';
}
