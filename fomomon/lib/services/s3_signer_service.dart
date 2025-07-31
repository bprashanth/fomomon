/// s3_signer_service.dart
/// ----------------------
/// Handles creating signed S3 URLs for authenticated uploads using AWS Signature V4.
/// This service takes temporary AWS credentials and creates signed URLs that can be
/// used to upload files directly to S3 with proper authentication.
/// See docs/signing.md for more details.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:amazon_cognito_identity_dart_2/sig_v4.dart';

import '../config/app_config.dart';

class S3SignerService {
  S3SignerService._privateConstructor();
  static final S3SignerService instance = S3SignerService._privateConstructor();

  String get _region => AppConfig.region;

  /// Create a presigned PUT URL for uploading a file to S3
  ///
  /// @param bucketName: The S3 bucket name
  /// @param s3Key: The S3 object key (file path in bucket)
  /// @param credentials: Temporary AWS credentials from Cognito Identity Pool
  /// @param contentType: Optional content type for the file
  /// @param expiresInMinutes: How long the presigned URL should be valid (default: 15 minutes)
  /// @return: Presigned S3 URL that can be used for PUT requests
  Future<String> createPresignedPutUrl({
    required String bucketName,
    required String s3Key,
    required Map<String, dynamic> credentials,
    String? contentType,
    int expiresInMinutes = 15,
  }) async {
    try {
      print('s3_signer_service: Creating presigned PUT URL for $s3Key');

      final datetime = SigV4.generateDatetime();
      final expiration =
          DateTime.now()
              .add(Duration(minutes: expiresInMinutes))
              .toUtc()
              .millisecondsSinceEpoch ~/
          1000; // Convert to Unix timestamp

      // Create the S3 endpoint URL
      final endpoint = 'https://$bucketName.s3.$_region.amazonaws.com';
      final url = '$endpoint/$s3Key';

      // Create the canonical request for presigned URL
      final canonicalRequest = _createCanonicalRequestForPresignedUrl(
        method: 'PUT',
        uri: '/$s3Key',
        queryParams: {
          'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
          'X-Amz-Credential': _buildCredential(
            credentials['accessKeyId'],
            datetime,
          ),
          'X-Amz-Date': datetime,
          'X-Amz-Expires': (expiresInMinutes * 60).toString(),
          'X-Amz-SignedHeaders':
              contentType != null ? 'host;content-type' : 'host',
          'X-Amz-Security-Token': credentials['sessionToken'],
        },
        headers: {
          'host': '$bucketName.s3.$_region.amazonaws.com',
          if (contentType != null) 'content-type': contentType,
        },
        payloadHash: 'UNSIGNED-PAYLOAD',
      );

      // Create string to sign
      final stringToSign = _createStringToSignForPresignedUrl(
        datetime: datetime,
        credentialScope: _buildCredentialScope(datetime),
        canonicalRequestHash: _hash(canonicalRequest),
      );

      // Calculate signature
      final signature = _calculateSignature(
        credentials['secretAccessKey'],
        datetime,
        stringToSign,
      );

      // Build the presigned URL
      final presignedUrl =
          '$url?'
          'X-Amz-Algorithm=AWS4-HMAC-SHA256&'
          'X-Amz-Credential=${Uri.encodeComponent(_buildCredential(credentials['accessKeyId'], datetime))}&'
          'X-Amz-Date=$datetime&'
          'X-Amz-Expires=${expiresInMinutes * 60}&'
          'X-Amz-SignedHeaders=${contentType != null ? 'host;content-type' : 'host'}&'
          'X-Amz-Security-Token=${Uri.encodeComponent(credentials['sessionToken'])}&'
          'X-Amz-Signature=$signature';

      print('s3_signer_service: Generated presigned PUT URL');
      return presignedUrl;
    } catch (e) {
      print('s3_signer_service: Failed to create presigned PUT URL: $e');
      rethrow;
    }
  }

  /// Create a presigned PUT URL for uploading JSON data to S3
  ///
  /// @param bucketName: The S3 bucket name
  /// @param s3Key: The S3 object key (file path in bucket)
  /// @param credentials: Temporary AWS credentials from Cognito Identity Pool
  /// @return: Presigned S3 URL that can be used for PUT requests
  Future<String> createPresignedJsonPutUrl({
    required String bucketName,
    required String s3Key,
    required Map<String, dynamic> credentials,
  }) async {
    return await createPresignedPutUrl(
      bucketName: bucketName,
      s3Key: s3Key,
      credentials: credentials,
      contentType: 'application/json',
    );
  }

  // Helper methods for AWS Signature V4
  String _hash(String input) {
    final hashBytes = SigV4.hash(utf8.encode(input));
    return hashBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('');
  }

  String _buildCredentialScope(String datetime) {
    return SigV4.buildCredentialScope(datetime, _region, 's3');
  }

  String _buildCredential(String accessKeyId, String datetime) {
    return '$accessKeyId/${_buildCredentialScope(datetime)}';
  }

  String _createCanonicalRequestForPresignedUrl({
    required String method,
    required String uri,
    required Map<String, String> queryParams,
    required Map<String, String> headers,
    required String payloadHash,
  }) {
    // Sort query parameters
    final sortedQueryParams =
        queryParams.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final canonicalQueryString = sortedQueryParams
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    // Sort headers
    final sortedHeaders =
        headers.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final canonicalHeaders =
        sortedHeaders
            .map((e) => '${e.key.toLowerCase()}:${e.value}')
            .join('\n') +
        '\n';
    final signedHeaders = sortedHeaders
        .map((e) => e.key.toLowerCase())
        .join(';');

    return [
      method,
      uri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
  }

  String _createStringToSignForPresignedUrl({
    required String datetime,
    required String credentialScope,
    required String canonicalRequestHash,
  }) {
    return [
      'AWS4-HMAC-SHA256',
      datetime,
      credentialScope,
      canonicalRequestHash,
    ].join('\n');
  }

  String _calculateSignature(
    String secretKey,
    String datetime,
    String stringToSign,
  ) {
    final signingKey = SigV4.calculateSigningKey(
      secretKey,
      datetime,
      _region,
      's3',
    );
    return SigV4.calculateSignature(signingKey, stringToSign);
  }
}
