/// Stub implementation of FlutterSecureStorage for web compilation.
/// On web, auth_service uses SharedPreferences instead of this class,
/// so none of these methods will be called at runtime.
class FlutterSecureStorage {
  const FlutterSecureStorage();
  Future<String?> read({required String key}) async => null;
  Future<void> write({required String key, required String value}) async {}
  Future<void> delete({required String key}) async {}
}
