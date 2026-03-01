/// AuthService.dart
/// ----------------
/// Currently, this service is coupled with the Cognito user pool.
/// Usage pattern:
///
/// final authService = AuthService.instance;
/// await authService.login(email, password);
/// final token = await authService.getValidToken();
/// if (token == null) {
///   // Force re-login via UI
/// }
///

import 'dart:convert';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    if (dart.library.html) '../stubs/flutter_secure_storage_stub.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_config.dart';
import '../config/app_config.dart';
import '../exceptions/auth_exceptions.dart';
import '../utils/log.dart';
import 'fetch_service.dart';

/// Authentication Service
///
/// **Session vs Token vs Credential:**
///
/// 1. **Session (CognitoUserSession)**: An object containing three JWT tokens:
///    - **ID Token**: Short-lived JWT (~1 hour) that proves user identity.
///    - **Access Token**: JWT for API authorization (not used in this app).
///    - **Refresh Token**: Long-lived token (~30 days) used to obtain new ID/Access tokens.
///
/// 2. **Token**: JWT strings. We store the refresh token. When upload is needed,
///    `getValidToken()` uses the refresh token to call Cognito and get a fresh ID token.
///
/// 3. **Credential**: AWS temporary credentials obtained by exchanging the ID token
///    with Cognito Identity Pool. Used to sign S3 requests via presigned URLs.
///
/// **Web note**: On web, flutter_secure_storage is replaced by SharedPreferences
/// (localStorage). This is intentional for Stage 0 — token security on web
/// is out-of-scope until Stage 1.
class AuthService {
  AuthService._privateConstructor();
  static final AuthService instance = AuthService._privateConstructor();

  AuthConfig? _authConfig;
  CognitoUserPool? _userPool;
  CognitoUser? _user;
  CognitoUserSession? _session;

  // Secure storage for persisting refresh token (native only).
  // On web the stub is imported but never called — SharedPreferences is used.
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Cached SharedPreferences instance for web.
  SharedPreferences? _prefs;

  // Storage keys
  static const String _refreshTokenKey = 'cognito_refresh_token';
  static const String _usernameKey = 'cognito_username';
  static const String _orgKey = 'cognito_org';

  // ---------------------------------------------------------------------------
  // Private helpers: read / write / delete a token key cross-platform.
  // On web: SharedPreferences (localStorage). On native: FlutterSecureStorage.
  // ---------------------------------------------------------------------------

  Future<String?> _readKey(String key) async {
    if (kIsWeb) {
      _prefs ??= await SharedPreferences.getInstance();
      return _prefs!.getString(key);
    }
    return await _secureStorage.read(key: key);
  }

  Future<void> _writeKey(String key, String value) async {
    if (kIsWeb) {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<void> _deleteKey(String key) async {
    if (kIsWeb) {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.remove(key);
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  // ---------------------------------------------------------------------------

  Future<String> getIdentityPoolId() async {
    if (_authConfig == null) {
      throw AuthConfigException(
        'Auth config not fetched. Call fetchAuthConfig() first.',
      );
    }
    return _authConfig!.identityPoolId;
  }

  Future<bool> isUserLoggedIn() async {
    if (_session != null) {
      dLog('auth_service: Session exists, returning true');
      return true;
    }
    final storedToken = await _readKey(_refreshTokenKey);
    dLog('auth_service: Stored refresh token: $storedToken');
    return storedToken != null;
  }

  /// Fetch AWS configuration from S3
  Future<AuthConfig> fetchAuthConfig() async {
    if (_authConfig != null) {
      return _authConfig!;
    }

    try {
      final bucketName = AppConfig.bucketName;
      final region = AppConfig.region;
      final configUrl =
          'https://$bucketName.s3.$region.amazonaws.com/auth_config.json';

      dLog('auth_service: Fetching auth config from $configUrl');
      final response = await FetchService.instance.fetchUnauthenticated(configUrl);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        _authConfig = AuthConfig.fromJson(json);

        _userPool = CognitoUserPool(
          _authConfig!.userPoolId,
          _authConfig!.clientId,
        );

        dLog('auth_service: Successfully fetched auth config: $_authConfig');
        return _authConfig!;
      } else {
        throw AuthConfigException(
          'Failed to fetch auth config: HTTP ${response.statusCode}',
        );
      }
    } on FormatException catch (e) {
      dLog('auth_service: Invalid JSON in auth config: $e');
      throw AuthConfigException(e);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Failed to fetch')) {
        dLog('auth_service: Network error fetching auth config: $e');
        throw AuthNetworkException(e);
      }
      dLog('auth_service: Failed to fetch auth config: $e');
      if (e is AuthException) rethrow;
      throw AuthConfigException(e);
    }
  }

  /// Get current auth config (throws if not fetched)
  AuthConfig get authConfig {
    if (_authConfig == null) {
      throw AuthConfigException(
        'Auth config not fetched. Call fetchAuthConfig() first.',
      );
    }
    return _authConfig!;
  }

  /// Login with email/password
  Future<void> login(String email, String password) async {
    if (_authConfig == null) {
      throw AuthConfigException(
        'Auth config not fetched. Call fetchAuthConfig() first.',
      );
    }

    _user = CognitoUser(email, _userPool!);

    final authDetails = AuthenticationDetails(
      username: email,
      password: password,
    );

    try {
      dLog('auth_service: Logging in user: $email');
      _session = await _user!.authenticateUser(authDetails);
      dLog('auth_service: Login successful for user: $email');

      if (_session!.refreshToken != null) {
        await _writeKey(_refreshTokenKey, _session!.refreshToken!.token ?? '');
        await _writeKey(_usernameKey, email);
        final org = AppConfig.org;
        if (org == null) {
          throw AuthConfigException(
            'AppConfig.org is not set. AppConfig.configure() must be called before login.',
          );
        }
        await _writeKey(_orgKey, org);
        dLog('auth_service: Stored refresh token and user info');
      }
    } on CognitoClientException catch (e) {
      dLog('auth_service: Cognito authentication failed: $e');
      if (e.code == 'NotAuthorizedException' ||
          e.code == 'UserNotFoundException' ||
          e.code == 'InvalidParameterException') {
        throw AuthCredentialsException(e);
      } else if (e.code == 'NetworkError') {
        throw AuthNetworkException(e);
      } else {
        throw AuthServiceException(e);
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Failed to fetch')) {
        dLog('auth_service: Network error during login: $e');
        throw AuthNetworkException(e);
      }
      dLog('auth_service: Unexpected error during login: $e');
      if (e is AuthException) rethrow;
      throw AuthServiceException(e);
    }
  }

  /// Restore minimal session info from stored refresh token (offline-only).
  Future<Map<String, String>?> restoreSessionOffline() async {
    try {
      final refreshToken = await _readKey(_refreshTokenKey);
      if (refreshToken == null) {
        dLog('auth_service: No stored refresh token found');
        return null;
      }

      final username = await _readKey(_usernameKey);
      final org = await _readKey(_orgKey);

      if (username == null || org == null) {
        dLog('auth_service: Stored token found but missing username or org');
        await _deleteKey(_refreshTokenKey);
        await _deleteKey(_usernameKey);
        await _deleteKey(_orgKey);
        return null;
      }

      dLog(
        'auth_service: Restored offline session info: $username, org: $org',
      );
      return {'username': username, 'org': org};
    } catch (e) {
      dLog('auth_service: Error restoring session: $e');
      await _deleteKey(_refreshTokenKey);
      await _deleteKey(_usernameKey);
      await _deleteKey(_orgKey);
      return null;
    }
  }

  /// Logout
  Future<void> logout() async {
    if (_user != null) {
      await _user!.signOut();
    }
    _session = null;
    await _deleteKey(_refreshTokenKey);
    await _deleteKey(_usernameKey);
    await _deleteKey(_orgKey);
    dLog('auth_service: Cleared stored session data');
  }

  /// Get a valid token from the session.
  /// If the session is invalid, refresh it.
  Future<String?> getValidToken() async {
    if (_session == null) {
      if (_authConfig == null) {
        try {
          await fetchAuthConfig();
        } catch (e) {
          dLog(
            'auth_service: Failed to fetch auth config for token refresh: $e',
          );
          throw AuthSessionExpiredException(
            'Cannot refresh token: auth config unavailable. Network required.',
          );
        }
      }

      final storedRefreshToken = await _readKey(_refreshTokenKey);
      if (storedRefreshToken != null) {
        final username = await _readKey(_usernameKey);
        if (username == null) {
          throw AuthSessionExpiredException(
            'Stored token found but missing username.',
          );
        }

        if (_user == null) {
          _user = CognitoUser(username, _userPool!);
        }

        dLog(
          'auth_service: No session but found stored refresh token, refreshing',
        );
        try {
          _session = await _user!.refreshSession(
            CognitoRefreshToken(storedRefreshToken),
          );
          dLog('auth_service: Session restored from stored refresh token');
          if (_session!.refreshToken != null) {
            await _writeKey(_refreshTokenKey, _session!.refreshToken!.token ?? '');
          }
          return _session!.idToken.jwtToken;
        } catch (e) {
          dLog(
            'auth_service: Failed to restore session from stored token: $e',
          );
          await _deleteKey(_refreshTokenKey);
          await _deleteKey(_usernameKey);
          await _deleteKey(_orgKey);
          throw AuthSessionExpiredException(e);
        }
      }
    }

    if (_session == null) {
      throw AuthSessionExpiredException(
        'No session available. User must log in.',
      );
    }

    if (_session!.isValid()) {
      dLog('auth_service: Session is valid, returning jwt token');
      return _session!.idToken.jwtToken;
    }

    if (_session!.refreshToken != null) {
      dLog('auth_service: Session is invalid, refreshing session');
      try {
        _session = await _user!.refreshSession(_session!.refreshToken!);
        dLog('auth_service: Session refreshed, returning jwt token');
        if (_session!.refreshToken != null) {
          await _writeKey(_refreshTokenKey, _session!.refreshToken!.token ?? '');
        }
        return _session!.idToken.jwtToken;
      } catch (e) {
        dLog('auth_service: Failed to refresh session: $e');
        _session = null;
        await _deleteKey(_refreshTokenKey);
        await _deleteKey(_usernameKey);
        await _deleteKey(_orgKey);
        throw AuthSessionExpiredException(e);
      }
    }

    _session = null;
    throw AuthSessionExpiredException(
      'Session expired and no refresh token available.',
    );
  }

  /// Get temporary AWS credentials for S3 uploads using Cognito Identity Pool
  Future<Map<String, dynamic>> getUploadCredentials() async {
    try {
      final idToken = await getValidToken();
      if (idToken == null) {
        throw AuthCredentialsException(
          'No valid ID token available. User must be logged in.',
        );
      }

      dLog('auth_service: Got valid ID token, length: ${idToken.length}');

      final credentials = CognitoCredentials(
        _authConfig!.identityPoolId,
        _userPool!,
      );
      await credentials.getAwsCredentials(idToken);

      dLog('auth_service: Successfully obtained temporary AWS credentials');

      return {
        'accessKeyId': credentials.accessKeyId,
        'secretAccessKey': credentials.secretAccessKey,
        'sessionToken': credentials.sessionToken,
      };
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Failed to fetch')) {
        dLog('auth_service: Network error getting upload credentials: $e');
        throw AuthNetworkException(e);
      }
      dLog('auth_service: Failed to get upload credentials: $e');
      if (e is AuthException) rethrow;
      throw AuthServiceException(e);
    }
  }
}
