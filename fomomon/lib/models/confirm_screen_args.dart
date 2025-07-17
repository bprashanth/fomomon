import '../models/site.dart';

// A collection of fields to pass to the confirm screen.
class ConfirmScreenArgs {
  final String? portraitImagePath;
  final String? landscapeImagePath;
  final String captureMode; // 'portrait' or 'landscape'
  final Site site;
  final String userId;
  final String name;
  final String email;
  final String org;

  ConfirmScreenArgs({
    this.portraitImagePath,
    this.landscapeImagePath,
    required this.captureMode,
    required this.site,
    required this.userId,
    required this.name,
    required this.email,
    required this.org,
  });
}
