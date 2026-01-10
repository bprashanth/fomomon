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

  // Configure is called at login, with the user info fields.
  static void configure({
    required String bucketName,
    String org = 't4gc',
    String region = 'ap-south-1',
  }) {
    _bucketName = bucketName;
    _org = org;
    _region = region;
  }

  // Configure guest mode
  static void configureGuestMode() {
    isGuestMode = true;
    _bucketName = 'fomomon';
    _org = guestOrg;
    _region = 'ap-south-1';
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
