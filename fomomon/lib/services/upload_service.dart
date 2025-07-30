/// upload_service.dart
/// -------------------
/// Handles uploading files and JSON to a S3 bucket. Responsibilities:
/// 1. Map sessions -> S3 bucket paths, eg:
///   bucketRoot + siteId/userId_timestamp_portrait.jpg
/// 2. Handle auth/cognito token
/// 3. Handle retries, rate limiting, etc.
///
/// Upload flow for a session:
/// 1. Upload portrait -> get URL
/// 2. Upload landscape -> get URL
/// 3. Upload session JSON
/// 4. Mark session uploaded
/// 5. Call onProgress() callback

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/captured_session.dart';
import '../models/site.dart';
import '../services/local_session_storage.dart';
import '../services/auth_service.dart';
import '../services/s3_signer_service.dart';
import '../config/app_config.dart';

class UploadService {
  // UploadService is a singleton
  UploadService._privateConstructor();
  static final UploadService instance = UploadService._privateConstructor();

  AuthService authService = AuthService.instance;
  final S3SignerService _s3SignerService = S3SignerService.instance;
  String get _region => AppConfig.region;

  // Upload all un-uploaded sessions to the bucketRoot of the matching site.
  //
  // @param onProgress: callback to update the UI with progress
  // @param sites: the sites.json object parsed into a list of Site objects
  // @throws: Exception if the upload fails.
  Future<void> uploadAllSessions({
    required List<Site> sites,
    required VoidCallback? onProgress,
  }) async {
    final sessions = await LocalSessionStorage.loadAllSessions();
    final unuploaded = sessions.where((s) => !s.isUploaded);

    for (final session in unuploaded) {
      await _uploadSession(session, sites);
      // await LocalSessionStorage.markSessionUploaded(session.sessionId);
      onProgress?.call();
    }
  }

  // Upload a single session to the bucketRoot of the matching site.
  Future<String> _uploadSession(
    CapturedSession session,
    List<Site> sites,
  ) async {
    final site = sites.firstWhere((s) => s.id == session.siteId);
    final timestampStr = _sanitizeTimestamp(session.timestamp);
    final portraitRemotePath =
        '${site.id}/${session.userId}_${timestampStr}_portrait.jpg';
    final landscapeRemotePath =
        '${site.id}/${session.userId}_${timestampStr}_landscape.jpg';

    final portraitUrl = await uploadFile(
      session.portraitImagePath,
      site.bucketRoot,
      portraitRemotePath,
    );

    final landscapeUrl = await uploadFile(
      session.landscapeImagePath,
      site.bucketRoot,
      landscapeRemotePath,
    );

    session.portraitImageUrl = portraitUrl;
    session.landscapeImageUrl = landscapeUrl;

    final sessionJsonPath = 'sessions/${session.userId}_${timestampStr}.json';
    final sessionUrl = await uploadJson(
      session.toJson(),
      site.bucketRoot,
      sessionJsonPath,
    );
    print(
      'upload_service: Session URL: $sessionUrl, portrait: $portraitUrl, landscape: $landscapeUrl',
    );
    return sessionUrl;
  }

  Future<String> uploadFile(
    String localPath,
    String bucketRoot,
    String remotePath,
  ) async {
    final fullUrl = _joinUrls(bucketRoot, remotePath);

    if (authService.isUserLoggedIn()) {
      return await _uploadFileAuth(localPath, fullUrl);
    }
    // This will fail if the user is not logged in.
    return await _uploadFileNoAuth(localPath, fullUrl);
  }

  Future<String> _uploadFileAuth(String localPath, String fullUrl) async {
    try {
      // Get temporary AWS credentials from AuthService
      final credentials = await authService.getUploadCredentials();

      // Parse bucket and key from the full URL
      final parsed = _parseS3Url(fullUrl);
      final bucket = parsed['bucket']!;
      final key = parsed['key']!;

      // Read the file
      final file = File(localPath);
      final bytes = await file.readAsBytes();
      final contentType = _getContentType(localPath);

      // Create presigned PUT URL
      final presignedUrl = await _s3SignerService.createPresignedPutUrl(
        bucketName: bucket,
        s3Key: key,
        credentials: credentials,
        contentType: contentType,
      );

      // Upload file using presigned URL
      print("upload_service: uploading to presigned URL");
      final response = await http.put(
        Uri.parse(presignedUrl),
        headers: {'Content-Type': contentType},
        body: bytes,
      );

      if (response.statusCode == 200) {
        print(
          'upload_service: Successfully uploaded $localPath using presigned URL',
        );
        return fullUrl; // Return the normal (non-signed) URL
      } else {
        print(
          'upload_service: Upload failed with status ${response.statusCode}',
        );
        print('upload_service: Response body: ${response.body}');
        print('upload_service: Response headers: ${response.headers}');
        throw Exception('File upload failed: ${response.statusCode}');
      }
    } catch (e) {
      print("upload_service: failed auth file upload $e");
      // Fallback to no-auth upload if authenticated upload fails
      return await _uploadFileNoAuth(localPath, fullUrl);
    }
  }

  Future<String> uploadJson(
    Map<String, dynamic> jsonData,
    String bucketRoot,
    String remotePath,
  ) async {
    final fullUrl = _joinUrls(bucketRoot, remotePath);

    if (authService.isUserLoggedIn()) {
      return await _uploadJsonAuth(jsonData, fullUrl);
    }
    // This will fail if the user is not logged in.
    return await _uploadJsonNoAuth(jsonData, fullUrl);
  }

  Future<String> _uploadJsonAuth(
    Map<String, dynamic> jsonData,
    String fullUrl,
  ) async {
    try {
      // Get temporary AWS credentials from AuthService
      final credentials = await authService.getUploadCredentials();

      // Parse bucket and key from the full URL
      final parsed = _parseS3Url(fullUrl);
      final bucket = parsed['bucket']!;
      final key = parsed['key']!;

      // Convert JSON to string
      final jsonString = jsonEncode(jsonData);
      final jsonBytes = utf8.encode(jsonString);

      // Create presigned PUT URL for JSON
      final presignedUrl = await _s3SignerService.createPresignedJsonPutUrl(
        bucketName: bucket,
        s3Key: key,
        credentials: credentials,
      );

      // Upload JSON using presigned URL
      final response = await http.put(
        Uri.parse(presignedUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonBytes,
      );

      if (response.statusCode == 200) {
        print('upload_service: Successfully uploaded JSON using presigned URL');
        return fullUrl; // Return the normal (non-signed) URL
      } else {
        throw Exception('JSON upload failed: ${response.statusCode}');
      }
    } catch (e) {
      print('upload_service: Authenticated JSON upload failed: $e');
      // Fallback to no-auth upload if authenticated upload fails
      return await _uploadJsonNoAuth(jsonData, fullUrl);
    }
  }

  // Internal helper for no-auth file uploads
  Future<String> _uploadFileNoAuth(String localPath, String fullUrl) async {
    final file = File(localPath);
    final bytes = await file.readAsBytes();
    final contentType = _getContentType(localPath);

    final response = await http.put(
      Uri.parse(fullUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );

    if (response.statusCode == 200) {
      return fullUrl;
    } else {
      throw Exception('File upload failed: ${response.statusCode}');
    }
  }

  Future<String> _uploadJsonNoAuth(
    Map<String, dynamic> jsonData,
    String fullUrl,
  ) async {
    final jsonString = jsonEncode(jsonData);
    final response = await http.put(
      Uri.parse(fullUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonString,
    );

    if (response.statusCode == 200) {
      return fullUrl;
    } else {
      throw Exception('JSON upload failed: ${response.statusCode}');
    }
  }

  String _getContentType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  /// Parse the bucket details from the full URL
  /// Example fullUrl: https://fomomon.s3.amazonaws.com/t4gc/left_6th/file.jpg
  /// @returns: Map<String, String>
  /// {
  ///   ' bucket': fomomon,
  ///   'key': t4gc/left_6th/file.jpg,
  ///   'region': ap-south-1
  /// }
  Map<String, String> _parseS3Url(String fullUrl) {
    final uri = Uri.parse(fullUrl);

    final hostParts = uri.host.split('.');
    final bucket = hostParts.first;

    final key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    return {'bucket': bucket, 'key': key, 'region': _region};
  }

  // Helper method to properly join URLs, handling trailing slashes
  String _joinUrls(String baseUrl, String path) {
    // Remove trailing slash from baseUrl if it exists
    final cleanBase =
        baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;
    // Remove leading slash from path if it exists
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    // Join with a single slash
    return '$cleanBase/$cleanPath';
  }

  String _sanitizeTimestamp(DateTime timestamp) {
    return timestamp.toIso8601String().replaceAll(':', '_');
  }
}
