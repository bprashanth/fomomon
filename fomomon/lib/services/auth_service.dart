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
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_config.dart';
import '../config/app_config.dart';
import '../exceptions/auth_exceptions.dart';

/// Authentication Service
///
/// **Session vs Token vs Credential:**
///
/// 1. **Session (CognitoUserSession)**: An object containing three JWT tokens:
///    - **ID Token**: Short-lived JWT (~1 hour) that proves user identity.
///      Used to exchange for AWS credentials via Cognito Identity Pool.
///    - **Access Token**: JWT for API authorization (not used in this app).
///    - **Refresh Token**: Long-lived token (~30 days) used to obtain new ID/Access tokens.
///      This is the token we persist securely for offline access.
///
/// 2. **Token**: JWT strings. We store the refresh token securely. When upload is needed,
///    `getValidToken()` uses the refresh token to call Cognito and get a fresh ID token.
///    Note: `user.refreshSession()` ALWAYS makes a network call to Cognito, even if the
///    current ID token isn't expired. The SDK doesn't cache - it always validates with Cognito.
///
/// 3. **Credential**: AWS temporary credentials (accessKeyId, secretAccessKey, sessionToken)
///    obtained by exchanging the ID token with Cognito Identity Pool. These are NOT sent as
///    HTTP bearer headers. Instead, they're used to sign S3 requests (via presigned URLs).
///
/// **Flow for Upload:**
/// 1. `getValidToken()` → Returns ID token (JWT string)
///    - If session exists and is valid: returns ID token immediately (no network call)
///    - If session invalid/missing: uses stored refresh token to call Cognito (network call)
///      to get new ID token
/// 2. `getUploadCredentials()` → Takes ID token, exchanges with Cognito Identity Pool
///    (network call) to get AWS temporary credentials
/// 3. AWS credentials used by S3SignerService to create presigned URLs for uploads
///
/// **Offline Behavior:**
/// - Stored refresh token acts as a "boolean" to bypass login screen
/// - No network calls until upload is attempted
/// - Auth config is only fetched when needed (during upload, which requires network anyway)
class AuthService {
  AuthService._privateConstructor();
  static final AuthService instance = AuthService._privateConstructor();

  AuthConfig? _authConfig;
  CognitoUserPool? _userPool;
  CognitoUser? _user;
  CognitoUserSession? _session;

  // Secure storage for persisting refresh token
  // Note: This storage pattern is backend-agnostic (works with Firebase Auth, etc.)
  // Only the refresh mechanism would need to change if swapping auth backends
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Storage keys for secure storage
  // Note: Storage is OS-encrypted (iOS Keychain, Android Keystore) until device unlock
  static const String _refreshTokenKey = 'cognito_refresh_token';
  static const String _usernameKey = 'cognito_username';
  static const String _orgKey = 'cognito_org';

  Future<String> getIdentityPoolId() async {
    if (_authConfig == null) {
      throw AuthConfigException(
        'Auth config not fetched. Call fetchAuthConfig() first.',
      );
    }
    return _authConfig!.identityPoolId;
  }

  /// Returns true if session exists (even if not validated) OR if a stored
  /// refresh token exists (indicating user has logged in before).
  /// Guest mode never calls login(), so returns false correctly.
  ///
  /// After a reboot, _session is null but a stored refresh token may exist.
  /// In this case, we return true so upload attempts will use auth path,
  /// which will then call getValidToken() to refresh the session.
  Future<bool> isUserLoggedIn() async {
    if (_session != null) {
      print('auth_service: Session exists, returning true');
      return true;
    }

    // Check for stored refresh token (indicates user has logged in before)
    final storedToken = await _secureStorage.read(key: _refreshTokenKey);
    print('auth_service: Stored refresh token: $storedToken');
    return storedToken != null;
  }

  /// Fetch AWS configuration from S3
  /// Uses AppConfig.bucketName to construct the S3 URL
  Future<AuthConfig> fetchAuthConfig() async {
    if (_authConfig != null) {
      return _authConfig!; // Return cached config
    }

    try {
      final bucketName = AppConfig.bucketName;
      final region = AppConfig.region;
      final configUrl =
          'https://$bucketName.s3.$region.amazonaws.com/auth_config.json';

      print('auth_service: Fetching auth config from $configUrl');
      final response = await http.get(Uri.parse(configUrl));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        _authConfig = AuthConfig.fromJson(json);

        // Initialize CognitoUserPool with fetched config
        _userPool = CognitoUserPool(
          _authConfig!.userPoolId,
          _authConfig!.clientId,
        );

        print('auth_service: Successfully fetched auth config: $_authConfig');
        return _authConfig!;
      } else {
        throw AuthConfigException(
          'Failed to fetch auth config: HTTP ${response.statusCode}',
        );
      }
    } on SocketException catch (e) {
      print('auth_service: Network error fetching auth config: $e');
      throw AuthNetworkException(e);
    } on FormatException catch (e) {
      print('auth_service: Invalid JSON in auth config: $e');
      throw AuthConfigException(e);
    } catch (e) {
      print('auth_service: Failed to fetch auth config: $e');
      if (e is AuthException) {
        rethrow;
      }
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
  ///
  /// @param email: the email of the user, but currently we accept userId /
  /// name too. This is simply the name field in the cognito user pool. See
  /// hack/update_as_user.py to see an example of how to set it.
  ///
  /// @param password: the password of the user. This is setup before hand. See
  /// hack/add_users.py for more details.
  Future<void> login(String email, String password) async {
    // Ensure config is fetched
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
      print('auth_service: Logging in user: $email');
      _session = await _user!.authenticateUser(authDetails);
      print('auth_service: Login successful for user: $email');

      // Refresh token stored via secure storage (encrypted until device
      // unlock). This enables offline app access after reboot.
      if (_session!.refreshToken != null) {
        await _secureStorage.write(
          key: _refreshTokenKey,
          value: _session!.refreshToken!.token,
        );
        // Store username and org for session restoration
        await _secureStorage.write(key: _usernameKey, value: email);
        // Get org from AppConfig (set during login flow before login() is called)
        final org = AppConfig.org;
        if (org == null) {
          throw AuthConfigException(
            'AppConfig.org is not set. AppConfig.configure() must be called before login.',
          );
        }
        await _secureStorage.write(key: _orgKey, value: org);
        print('auth_service: Stored refresh token and user info securely');
      }
    } on CognitoClientException catch (e) {
      print('auth_service: Cognito authentication failed: $e');
      // Check for specific Cognito error codes
      if (e.code == 'NotAuthorizedException' ||
          e.code == 'UserNotFoundException' ||
          e.code == 'InvalidParameterException') {
        throw AuthCredentialsException(e);
      } else if (e.code == 'NetworkError') {
        throw AuthNetworkException(e);
      } else {
        throw AuthServiceException(e);
      }
    } on SocketException catch (e) {
      print('auth_service: Network error during login: $e');
      throw AuthNetworkException(e);
    } catch (e) {
      print('auth_service: Unexpected error during login: $e');
      if (e is AuthException) {
        rethrow;
      }
      throw AuthServiceException(e);
    }
  }

  /// Restore minimal session info from stored refresh token (offline-only).
  /// This creates a "thin" session that only contains stored user info (username, org)
  /// and does NOT create a full CognitoUserSession needed for uploads.
  ///
  /// **Why defer full session restoration to upload time?**
  ///
  /// Creating a full session requires:
  /// 1. Fetching auth config from S3 (network call)
  /// 2. Creating CognitoUser object (needs auth config)
  /// 3. Calling refreshSession() to validate refresh token (network call to Cognito)
  ///
  /// By deferring this until upload time, we achieve:
  /// - **Offline-first access**: Users can access the app immediately after reboot
  ///   without waiting for network calls, using cached sites/images
  /// - **No blocking startup**: App startup is fast and doesn't fail if offline
  /// - **Lazy validation**: Token validation only happens when actually needed (upload)
  ///
  /// The stored refresh token acts as a "has logged in" boolean to bypass the login
  /// screen. Full session restoration happens in `getValidToken()` when upload is
  /// attempted (which requires network anyway).
  ///
  /// @return: Map with 'username' and 'org' if stored token exists, null otherwise
  Future<Map<String, String>?> restoreSessionOffline() async {
    try {
      // Check for stored refresh token
      final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (refreshToken == null) {
        print('auth_service: No stored refresh token found');
        return null;
      }

      final username = await _secureStorage.read(key: _usernameKey);
      final org = await _secureStorage.read(key: _orgKey);

      if (username == null || org == null) {
        print('auth_service: Stored token found but missing username or org');
        // Clear incomplete data
        await _secureStorage.delete(key: _refreshTokenKey);
        await _secureStorage.delete(key: _usernameKey);
        await _secureStorage.delete(key: _orgKey);
        return null;
      }

      // Don't fetch auth config here - it's not needed to use token as boolean.
      // Auth config will be fetched when getValidToken() is called (during upload).
      // This allows offline app access after reboot without blocking on network.

      // Note: We don't create CognitoUser here because we need auth config for that.
      // CognitoUser will be created in getValidToken() when auth config is available.
      // For now, just return user info to bypass login screen.

      print(
        'auth_service: Restored offline session info: $username, org: $org',
      );
      return {'username': username, 'org': org};
    } catch (e) {
      print('auth_service: Error restoring session: $e');
      // Clear potentially corrupted data
      await _secureStorage.delete(key: _refreshTokenKey);
      await _secureStorage.delete(key: _usernameKey);
      await _secureStorage.delete(key: _orgKey);
      return null;
    }
  }

  /// Logout
  Future<void> logout() async {
    if (_user != null) {
      await _user!.signOut();
    }
    _session = null;
    // Clear stored refresh token, username, and org from secure storage
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _usernameKey);
    await _secureStorage.delete(key: _orgKey);
    print('auth_service: Cleared stored session data');
  }

  /// Get a valid token from the session.
  /// If the session is invalid, refresh it.
  ///
  /// @return: the valid token
  /// @throws: AuthSessionExpiredException if the session is invalid and cannot be refreshed
  Future<String?> getValidToken() async {
    // If no session but we have a stored refresh token, try to restore it
    // First ensure we have auth config (required for CognitoUserPool).
    // See file comment for session vs token vs credential.
    if (_session == null) {
      // Try to fetch auth config if not available (needed for CognitoUser)
      if (_authConfig == null) {
        try {
          await fetchAuthConfig();
        } catch (e) {
          print(
            'auth_service: Failed to fetch auth config for token refresh: $e',
          );
          throw AuthSessionExpiredException(
            'Cannot refresh token: auth config unavailable. Network required.',
          );
        }
      }

      // Check for stored refresh token
      final storedRefreshToken = await _secureStorage.read(
        key: _refreshTokenKey,
      );
      if (storedRefreshToken != null) {
        // Get username from stored data
        final username = await _secureStorage.read(key: _usernameKey);
        if (username == null) {
          throw AuthSessionExpiredException(
            'Stored token found but missing username.',
          );
        }

        // Create CognitoUser if not already created
        if (_user == null) {
          _user = CognitoUser(username, _userPool!);
        }

        // Note: We always call refreshSession() here because we don't have a session object yet.
        // refreshSession() will make a network call to Cognito to validate the refresh token
        // and get a new ID token. There's no way to check if a refresh token is valid without
        // calling Cognito, so we can't avoid the network call.
        print(
          'auth_service: No session but found stored refresh token, refreshing',
        );
        try {
          _session = await _user!.refreshSession(
            CognitoRefreshToken(storedRefreshToken),
          );
          print('auth_service: Session restored from stored refresh token');
          // Update stored refresh token if it changed
          if (_session!.refreshToken != null) {
            await _secureStorage.write(
              key: _refreshTokenKey,
              value: _session!.refreshToken!.token,
            );
          }
          return _session!.idToken.jwtToken;
        } catch (e) {
          print(
            'auth_service: Failed to restore session from stored token: $e',
          );
          // Clear invalid stored token
          await _secureStorage.delete(key: _refreshTokenKey);
          await _secureStorage.delete(key: _usernameKey);
          await _secureStorage.delete(key: _orgKey);
          throw AuthSessionExpiredException(e);
        }
      }
    }

    // If we still don't have a session after checking stored token, fail
    if (_session == null) {
      throw AuthSessionExpiredException(
        'No session available. User must log in.',
      );
    }

    // If session is valid, return it
    if (_session!.isValid()) {
      print('auth_service: Session is valid, returning jwt token');
      return _session!.idToken.jwtToken;
    }

    // Session is invalid, try to refresh
    if (_session!.refreshToken != null) {
      print('auth_service: Session is invalid, refreshing session');
      try {
        _session = await _user!.refreshSession(_session!.refreshToken!);
        print('auth_service: Session refreshed, returning jwt token');
        // Update stored refresh token if it changed
        if (_session!.refreshToken != null) {
          await _secureStorage.write(
            key: _refreshTokenKey,
            value: _session!.refreshToken!.token,
          );
        }
        return _session!.idToken.jwtToken;
      } catch (e) {
        print('auth_service: Failed to refresh session: $e');
        // Clear invalid session
        _session = null;
        await _secureStorage.delete(key: _refreshTokenKey);
        await _secureStorage.delete(key: _usernameKey);
        await _secureStorage.delete(key: _orgKey);
        throw AuthSessionExpiredException(e);
      }
    }

    // No refresh token available
    _session = null;
    throw AuthSessionExpiredException(
      'Session expired and no refresh token available.',
    );
  }

  /// Get temporary AWS credentials for S3 uploads using Cognito Identity Pool
  ///
  /// @return: Map containing temporary AWS credentials (accessKeyId, secretAccessKey, sessionToken)
  /// @throws: Exception if user is not logged in or credentials cannot be obtained
  Future<Map<String, dynamic>> getUploadCredentials() async {
    try {
      // Get the ID token from the current session
      final idToken = await getValidToken();
      if (idToken == null) {
        throw AuthCredentialsException(
          'No valid ID token available. User must be logged in.',
        );
      }

      print('auth_service: Got valid ID token, length: ${idToken.length}');

      // Create CognitoCredentials instance and get temporary AWS credentials
      final credentials = CognitoCredentials(
        _authConfig!.identityPoolId,
        _userPool!,
      );
      await credentials.getAwsCredentials(idToken);

      print('auth_service: Successfully obtained temporary AWS credentials');
      print('auth_service: Access Key ID: ${credentials.accessKeyId}');
      print(
        'auth_service: Secret Access Key length: ${credentials.secretAccessKey?.length ?? 0}',
      );
      print(
        'auth_service: Session Token length: ${credentials.sessionToken?.length ?? 0}',
      );

      return {
        'accessKeyId': credentials.accessKeyId,
        'secretAccessKey': credentials.secretAccessKey,
        'sessionToken': credentials.sessionToken,
      };
    } on SocketException catch (e) {
      print('auth_service: Network error getting upload credentials: $e');
      throw AuthNetworkException(e);
    } catch (e) {
      print('auth_service: Failed to get upload credentials: $e');
      if (e is AuthException) {
        rethrow;
      }
      throw AuthServiceException(e);
    }
  }
}
