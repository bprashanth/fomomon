/// s3_signer_service.dart
/// ----------------------
/// Handles creating signed S3 URLs for authenticated uploads and downloads using AWS Signature V4.
/// Takes temporary AWS credentials and creates presigned URLs for PUT (upload) or GET (download).
/// See docs/signing.md for more details.

import 'dart:convert';

import 'package:amazon_cognito_identity_dart_2/sig_v4.dart';

import '../config/app_config.dart';
import '../utils/log.dart';

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
      dLog('s3_signer_service: Creating presigned PUT URL for $s3Key');
      return _createPresignedUrl(
        bucketName: bucketName,
        s3Key: s3Key,
        credentials: credentials,
        method: 'PUT',
        contentType: contentType,
        expiresInMinutes: expiresInMinutes,
      );
    } catch (e) {
      dLog('s3_signer_service: Failed to create presigned PUT URL: $e');
      rethrow;
    }
  }

  /// Create a presigned GET URL for downloading an object from S3
  ///
  /// @param bucketName: The S3 bucket name
  /// @param s3Key: The S3 object key (file path in bucket)
  /// @param credentials: Temporary AWS credentials from Cognito Identity Pool
  /// @param expiresInMinutes: How long the presigned URL should be valid (default: 15 minutes)
  /// @return: Presigned S3 URL that can be used for GET requests
  Future<String> createPresignedGetUrl({
    required String bucketName,
    required String s3Key,
    required Map<String, dynamic> credentials,
    int expiresInMinutes = 15,
  }) async {
    try {
      dLog('s3_signer_service: Creating presigned GET URL for $s3Key');
      return _createPresignedUrl(
        bucketName: bucketName,
        s3Key: s3Key,
        credentials: credentials,
        method: 'GET',
        expiresInMinutes: expiresInMinutes,
      );
    } catch (e) {
      dLog('s3_signer_service: Failed to create presigned GET URL: $e');
      rethrow;
    }
  }

  /// Shared presigning path for GET and PUT. No duplicated canonical-request or signature logic.
  String _createPresignedUrl({
    required String bucketName,
    required String s3Key,
    required Map<String, dynamic> credentials,
    required String method,
    String? contentType,
    int expiresInMinutes = 15,
  }) {
    final datetime = SigV4.generateDatetime();
    final host = '$bucketName.s3.$_region.amazonaws.com';
    final endpoint = 'https://$host';
    final url = '$endpoint/$s3Key';
    final signedHeaders = contentType != null ? 'host;content-type' : 'host';

    final canonicalRequest = _createCanonicalRequestForPresignedUrl(
      method: method,
      uri: '/$s3Key',
      queryParams: {
        'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
        'X-Amz-Credential': _buildCredential(
          credentials['accessKeyId'],
          datetime,
        ),
        'X-Amz-Date': datetime,
        'X-Amz-Expires': (expiresInMinutes * 60).toString(),
        'X-Amz-SignedHeaders': signedHeaders,
        'X-Amz-Security-Token': credentials['sessionToken'],
      },
      headers: {
        'host': host,
        if (contentType != null) 'content-type': contentType,
      },
      payloadHash: 'UNSIGNED-PAYLOAD',
    );

    final stringToSign = _createStringToSignForPresignedUrl(
      datetime: datetime,
      credentialScope: _buildCredentialScope(datetime),
      canonicalRequestHash: _hash(canonicalRequest),
    );

    final signature = _calculateSignature(
      credentials['secretAccessKey'],
      datetime,
      stringToSign,
    );

    return '$url?'
        'X-Amz-Algorithm=AWS4-HMAC-SHA256&'
        'X-Amz-Credential=${Uri.encodeComponent(_buildCredential(credentials['accessKeyId'], datetime))}&'
        'X-Amz-Date=$datetime&'
        'X-Amz-Expires=${expiresInMinutes * 60}&'
        'X-Amz-SignedHeaders=${Uri.encodeComponent(signedHeaders)}&'
        'X-Amz-Security-Token=${Uri.encodeComponent(credentials['sessionToken'])}&'
        'X-Amz-Signature=$signature';
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
