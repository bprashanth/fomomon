/// fetch_service.dart
/// ------------------
/// Single place for HTTP GETs. Use fetchUnauthenticated for public URLs
/// (e.g. auth_config.json) and fetch(bucket, key) for S3 objects via presigned GET.

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 's3_signer_service.dart';

class FetchService {
  FetchService._privateConstructor();
  static final FetchService instance = FetchService._privateConstructor();

  /// Fetches a URL without authentication. Use for public resources (e.g. auth_config.json).
  Future<http.Response> fetchUnauthenticated(String url) {
    return http.get(Uri.parse(url));
  }

  /// Fetches an S3 object using a presigned GET URL (credentials from AuthService).
  Future<http.Response> fetch(String bucketName, String s3Key) async {
    final credentials = await AuthService.instance.getUploadCredentials();
    final presignedUrl = await S3SignerService.instance.createPresignedGetUrl(
      bucketName: bucketName,
      s3Key: s3Key,
      credentials: credentials,
    );
    return http.get(Uri.parse(presignedUrl));
  }

  /// Derives the S3 object key from a full S3 URL (path without leading slash).
  ///
  /// Example:
  ///   https://fomomon.s3.ap-south-1.amazonaws.com/t4gc/foo/bar.jpg
  ///   → t4gc/foo/bar.jpg
  static String s3KeyFromUrl(String fullS3Url) {
    final path = Uri.parse(fullS3Url).path;
    return path.startsWith('/') ? path.substring(1) : path;
  }
}
