// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

// Locks the screen to the given orientation using the browser Screen
// Orientation API. Works for installed PWAs (display: standalone).
// Silently swallows errors — if lock() is unsupported (plain browser tab,
// older browser), the user must rotate manually.
Future<void> lockScreenOrientation(String mode) async {
  try {
    await html.window.screen?.orientation?.lock(mode);
  } catch (_) {}
}

// Releases any orientation lock set by lockScreenOrientation().
void unlockScreenOrientation() {
  try {
    html.window.screen?.orientation?.unlock();
  } catch (_) {}
}
