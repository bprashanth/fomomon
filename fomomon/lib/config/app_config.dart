class AppConfig {
  // The "local" and "mock" variables used here are only used in testing mode.
  static bool isTestMode = true;
  static bool isGuestMode = false;
  // Path to a local directory, trailing slash is optional
  static String? _localRoot;
  static double? mockLat = 10.31344;
  static double? mockLng = 76.83704;

  // Production variables
  static String? _bucketName;
  static String? _org;
  static String? _region;

  // Defaults (centralized)
  static const String defaultBucketName = 'fomomon';
  static const String defaultRegion = 'ap-south-1';
  static const String defaultOrg = 't4gc';

  // Guest mode variables
  static const String guestUser = 'Srini';
  static const String guestEmail = 'srini@ncf-india.org';
  static const String guestOrg = 'ncf';

  // Default bucket for guest mode when no sites are available
  static const String guestBucket =
      'https://fomomonguest.s3.ap-south-1.amazonaws.com/';

  // Organization data mapping org codes to default values
  static const Map<String, Map<String, String>> organizationData = {
    't4gc': {'email': 'prashanth@tech4goodcommunity.com', 'name': 'Prashanth'},
    'testorg': {'email': 'hari@foundation', 'name': 'asimov'},
    'ncf': {'email': 'srini@ncf-india.org', 'name': 'Srini'},
  };

  // Configure is called at login / restore, with the org.
  // Bucket name and region are intentionally centralized here.
  static void configure([String org = defaultOrg]) {
    _bucketName = defaultBucketName;
    _org = org;
    _region = defaultRegion;
  }

  // Configure guest mode.
  // See `guest_sites.dart` header for a detailed explanation of how guest mode
  // uses a hardcoded public bucket (`guestBucket`) and bypasses Cognito auth
  // for uploads (no-auth upload path to a public S3 bucket).
  static void configureGuestMode() {
    isGuestMode = true;
    _bucketName = defaultBucketName;
    _org = guestOrg;
    _region = defaultRegion;
  }

  // Reset guest mode
  static void resetGuestMode() {
    isGuestMode = false;
  }

  static void setLocalRoot(String path) {
    _localRoot = path;
  }

  static void setOrg(String org) {
    _org = org;
  }

  static String get bucketName {
    if (_bucketName == null) {
      throw Exception('AppConfig is not configured with bucketName');
    }
    return _bucketName!;
  }

  static String get region {
    if (_region == null) {
      throw Exception('AppConfig is not configured with region');
    }
    return _region!;
  }

  static String? get org => _org;

  static String getResolvedBucketRoot() {
    String bucketRoot = "";
    if (isTestMode && _localRoot != null) {
      bucketRoot = _localRoot!;
    } else if (_bucketName != null && _org != null) {
      bucketRoot = "https://${_bucketName!}.s3.amazonaws.com/${_org!}";
    } else {
      throw Exception('AppConfig is not configured with bucketName/org');
    }
    return bucketRoot.endsWith('/')
        ? bucketRoot.substring(0, bucketRoot.length - 1)
        : bucketRoot;
  }
}
