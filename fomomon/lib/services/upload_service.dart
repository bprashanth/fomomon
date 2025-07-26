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

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/captured_session.dart';
import '../models/site.dart';
import '../services/local_session_storage.dart';

class UploadService {
  // UploadService is a singleton
  UploadService._privateConstructor();
  static final UploadService instance = UploadService._privateConstructor();

  // TODO(prashanth@): future auth/cognito token
  String? idToken;

  // Upload all un-uploaded sessions to the bucketRoot of the matching site.
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

    if (idToken == null) {
      return await _uploadFileNoAuth(localPath, fullUrl);
    } else {
      return await _uploadFileNoAuth(localPath, fullUrl);
    }
  }

  Future<String> uploadJson(
    Map<String, dynamic> jsonData,
    String bucketRoot,
    String remotePath,
  ) async {
    final fullUrl = _joinUrls(bucketRoot, remotePath);

    if (idToken == null) {
      return await _uploadJsonNoAuth(jsonData, fullUrl);
    }
    return await _uploadJsonNoAuth(jsonData, fullUrl);
  }

  // Internal helper for no-auth file uploads
  Future<String> _uploadFileNoAuth(String localPath, String fullUrl) async {
    final file = File(localPath);
    final bytes = await file.readAsBytes();

    print('upload_service: Uploading file from $localPath to $fullUrl');
    final response = await http.put(
      Uri.parse(fullUrl),
      headers: {'Content-Type': 'application/octet-stream'},
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

  void setToken(String? token) {
    idToken = token;
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
