// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

// Calls getUserMedia({video: true}) to trigger the browser's camera permission
// dialog, then immediately stops the stream. After this resolves, subsequent
// calls to availableCameras() return valid camera descriptions.
// Throws if permission is denied — caller should catch and show a message.
Future<void> requestCameraPermission() async {
  final stream = await html.window.navigator.mediaDevices!
      .getUserMedia({'video': true});
  for (final track in stream.getTracks()) {
    track.stop();
  }
}
