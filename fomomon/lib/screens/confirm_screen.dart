import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/heading_service.dart';
import '../utils/screen_orientation.dart';
import '../services/local_image_storage.dart';
import '../models/confirm_screen_args.dart';
import '../screens/capture_screen.dart';
import '../screens/survey_screen.dart';
import '../models/captured_session.dart';
import '../models/survey_response.dart';
import '../services/local_session_storage.dart';
import '../screens/home_screen.dart';

class ConfirmScreen extends StatefulWidget {
  final ConfirmScreenArgs args;

  const ConfirmScreen({super.key, required this.args});

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late ConfirmScreenArgs args;
  late String _shownImagePath;
  // Bytes for the captured image — loaded once in initState to avoid repeated
  // disk reads (native) or map lookups (web) inside build().
  late Uint8List _imageBytes;

  @override
  void initState() {
    super.initState();
    lockScreenOrientation('portrait');
    args = widget.args;
    _shownImagePath =
        args.captureMode == 'portrait'
            ? args.portraitImagePath!
            : args.landscapeImagePath!;
    // LocalImageStorage.readBytes is synchronous.
    // Native: File(path).readAsBytesSync() — fast for a recently-captured JPEG.
    // Web:    looks up 'web_img:{key}' from the in-memory store.
    _imageBytes = LocalImageStorage.readBytes(_shownImagePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_imageBytes, fit: BoxFit.cover),

          // Retake button
          Positioned(
            bottom: 60,
            left: 30,
            child: SizedBox(
              width: 150,
              child: ElevatedButton.icon(
                onPressed: () => _onRetake(context, _shownImagePath),
                icon: const Icon(Icons.close),
                label: const Text('Retake'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(229, 54, 22, 19),
                  foregroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(40),
                    side: const BorderSide(color: Colors.red, width: 2),
                  ),
                ),
              ),
            ),
          ),

          // Confirm button
          Positioned(
            bottom: 60,
            right: 30,
            child: SizedBox(
              width: 150,
              child: ElevatedButton.icon(
                onPressed: () => _onConfirm(context, args, _shownImagePath),
                icon: const Icon(Icons.check),
                label: const Text('Use Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(229, 22, 54, 19),
                  foregroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(40),
                    side: const BorderSide(color: Colors.green, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onRetake(BuildContext context, String path) async {
    try {
      // Cross-platform delete: removes file on native, map entry on web.
      await LocalImageStorage.deleteImage(path);
    } catch (e) {
      print('Error deleting image: $e');
    }

    // Pre-rotate before popping back to CaptureScreen so the transition
    // is smooth. On native: SystemChrome. On web: screen.orientation.lock().
    await lockScreenOrientation(
      args.captureMode == 'landscape' ? 'landscape' : 'portrait',
    );

    Navigator.of(context).pop(); // go back to CaptureScreen
  }

  void _onConfirm(
    BuildContext context,
    ConfirmScreenArgs args,
    String imagePath,
  ) async {
    final timestamp = DateTime.now();
    // saveImageToPermanentLocation is cross-platform:
    // - Native: path from saveImage() is already permanent; returns as-is.
    // - Web:    path is 'web_img:{key}'; bytes already in store; returns as-is.
    final savedPath = await LocalImageStorage.saveImageToPermanentLocation(
      tempPath: imagePath,
      userId: args.userId,
      siteId: args.site.id,
      captureMode: args.captureMode,
      timestamp: timestamp,
    );

    if (!context.mounted) return;

    if (args.captureMode == 'portrait') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder:
              (_) => CaptureScreen(
                portraitImagePath: savedPath,
                captureMode: 'landscape',
                site: args.site,
                userId: args.userId,
                name: args.name,
                email: args.email,
                org: args.org,
              ),
        ),
      );
    } else {
      if (args.site.surveyQuestions.isEmpty) {
        final heading = await HeadingService.getCurrentHeadingOnce();

        final session = CapturedSession(
          sessionId: '${args.userId}_${timestamp.toIso8601String()}',
          siteId: args.site.id,
          latitude: args.site.lat,
          longitude: args.site.lng,
          heading: heading,
          portraitImagePath: args.portraitImagePath!,
          landscapeImagePath: savedPath,
          responses: <SurveyResponse>[],
          timestamp: timestamp,
          userId: args.userId,
        );

        await LocalSessionStorage.saveSession(session);
        if (!context.mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder:
                (_) => HomeScreen(
                  name: args.name,
                  email: args.email,
                  org: args.org,
                ),
          ),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (_) => SurveyScreen(
                  userId: args.userId,
                  site: args.site,
                  portraitImagePath: args.portraitImagePath!,
                  landscapeImagePath: savedPath,
                  timestamp: timestamp,
                  name: args.name,
                  email: args.email,
                  org: args.org,
                ),
          ),
        );
      }
    }
  }
}
