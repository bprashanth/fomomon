import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/local_image_storage.dart';
import '../models/confirm_screen_args.dart';
import '../screens/capture_screen.dart';
import '../screens/survey_screen.dart';

class ConfirmScreen extends StatefulWidget {
  final ConfirmScreenArgs args;

  const ConfirmScreen({super.key, required this.args});

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late ConfirmScreenArgs args;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    args = widget.args;
  }

  @override
  Widget build(BuildContext context) {
    final String shownImagePath =
        args.captureMode == 'portrait'
            ? args.portraitImagePath!
            : args.landscapeImagePath!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(shownImagePath), fit: BoxFit.cover),

          // Retake button
          Positioned(
            bottom: 60,
            left: 30,
            child: SizedBox(
              width: 150,
              child: ElevatedButton.icon(
                onPressed: () => _onRetake(context, shownImagePath),
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
                onPressed: () => _onConfirm(context, args, shownImagePath),
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
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting file: $e');
    }

    if (args.captureMode == 'landscape') {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }

    Navigator.of(context).pop(); // go back to CaptureScreen
  }

  void _onConfirm(
    BuildContext context,
    ConfirmScreenArgs args,
    String imagePath,
  ) async {
    final timestamp = DateTime.now();
    final savedPath = await LocalImageStorage.saveImageToPermanentLocation(
      tempPath: imagePath,
      userId: args.userId,
      siteId: args.site.id,
      captureMode: args.captureMode,
      timestamp: timestamp,
    );

    if (!context.mounted) return;

    if (args.captureMode == 'portrait') {
      // Launch next capture
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
      // Launch survey
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
