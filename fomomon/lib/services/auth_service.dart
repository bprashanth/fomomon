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

import '../models/auth_config.dart';
import '../config/app_config.dart';
import '../exceptions/auth_exceptions.dart';

class AuthService {
  AuthService._privateConstructor();
  static final AuthService instance = AuthService._privateConstructor();

  AuthConfig? _authConfig;
  CognitoUserPool? _userPool;
  CognitoUser? _user;
  CognitoUserSession? _session;

  Future<String> getIdentityPoolId() async {
    if (_authConfig == null) {
      throw AuthConfigException(
        'Auth config not fetched. Call fetchAuthConfig() first.',
      );
    }
    return _authConfig!.identityPoolId;
  }

  bool isUserLoggedIn() {
    return _session != null;
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

  /// Logout
  Future<void> logout() async {
    await _user!.signOut();
    _session = null;
  }

  /// Get a valid token from the session.
  /// If the session is invalid, refresh it.
  ///
  /// @return: the valid token, or null if the session is invalid and cannot be
  /// refreshed. The caller must pay heed to null and force re-login.
  Future<String?> getValidToken() async {
    if (_session == null) return null;

    if (_session!.isValid()) {
      print('auth_service: Session is valid, returning jwt token');
      return _session!.idToken.jwtToken;
    }

    if (_session!.refreshToken != null) {
      print('auth_service: Session is invalid, refreshing session');
      try {
        _session = await _user!.refreshSession(_session!.refreshToken!);
        print('auth_service: Session refreshed, returning jwt token');
        return _session!.idToken.jwtToken;
      } catch (e) {
        print('auth_service: Failed to refresh session: $e');
        return null;
      }
    }

    return null;
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
