/// AuthConfig model
/// Contains AWS Cognito pool configuration for authentication
class AuthConfig {
  final String userPoolId;
  final String clientId;
  final String identityPoolId;

  AuthConfig({
    required this.userPoolId,
    required this.clientId,
    required this.identityPoolId,
  });

  factory AuthConfig.fromJson(Map<String, dynamic> json) {
    return AuthConfig(
      userPoolId: json['userPoolId'],
      clientId: json['clientId'],
      identityPoolId: json['identityPoolId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userPoolId': userPoolId,
      'clientId': clientId,
      'identityPoolId': identityPoolId,
    };
  }

  @override
  String toString() {
    return 'AuthConfig(userPoolId: $userPoolId, clientId: $clientId, identityPoolId: $identityPoolId)';
  }
}
