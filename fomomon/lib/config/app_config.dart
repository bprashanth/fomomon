class AppConfig {
  // The "local" and "mock" variables used here are only used in testing mode.
  static bool isTestMode = false;
  // Path to a local directory, trailing slash is optional
  static String? _localRoot;
  static double? mockLat;
  static double? mockLng;

  // Production variables
  static String? _bucketName;
  static String? _org;

  // Configure is called only once, at login, with the user info fields.
  static void configure({required String bucketName, required String org}) {
    _bucketName = bucketName;
    _org = org;
  }

  static void setLocalRoot(String path) {
    _localRoot = path;
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
