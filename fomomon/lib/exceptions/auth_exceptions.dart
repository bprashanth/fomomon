/// Authentication-related exceptions
/// Provides specific exception types for different authentication scenarios

/// Base class for authentication exceptions
abstract class AuthException implements Exception {
  final String message;
  final dynamic originalError;

  AuthException(this.message, [this.originalError]);

  @override
  String toString() => 'AuthException: $message';
}

/// Thrown when network connectivity issues prevent authentication
class AuthNetworkException extends AuthException {
  AuthNetworkException([dynamic originalError])
    : super(
        'Network error: Unable to contact authentication services',
        originalError,
      );
}

/// Thrown when AWS configuration cannot be fetched
class AuthConfigException extends AuthException {
  AuthConfigException([dynamic originalError])
    : super(
        'Configuration error: Unable to fetch authentication configuration',
        originalError,
      );
}

/// Thrown when user credentials are invalid
class AuthCredentialsException extends AuthException {
  AuthCredentialsException([dynamic originalError])
    : super(
        'Invalid credentials: Username or password is incorrect',
        originalError,
      );
}

/// Thrown when the authentication service is unavailable
class AuthServiceException extends AuthException {
  AuthServiceException([dynamic originalError])
    : super(
        'Service error: Authentication service is temporarily unavailable',
        originalError,
      );
}
