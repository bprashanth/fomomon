/// LoginError enum
/// Defines different types of errors that can occur during login
enum LoginError {
  invalidCredentials, // Bad username/password
  configFetchFailed, // Can't fetch AWS config
  networkError, // No internet connection
  configInvalid, // Malformed config JSON
  unknown, // Other errors
}

extension LoginErrorExtension on LoginError {
  String get message {
    switch (this) {
      case LoginError.invalidCredentials:
        return 'Invalid username or password.';
      case LoginError.configFetchFailed:
        return 'Unable to connect to authentication service. Please check your internet connection.';
      case LoginError.networkError:
        return 'No internet connection. Please try again.';
      case LoginError.configInvalid:
        return 'Authentication service configuration error. Please contact support.';
      case LoginError.unknown:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}
