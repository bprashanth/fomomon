import 'package:flutter/services.dart';

// Native implementation — delegates to SystemChrome.setPreferredOrientations().
// lockScreenOrientation() mirrors what capture_screen.dart does in initState.
// unlockScreenOrientation() restores all orientations so subsequent screens
// are not stuck in the orientation the capture screen set.
Future<void> lockScreenOrientation(String mode) async {
  if (mode == 'landscape') {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }
}

void unlockScreenOrientation() {
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}
