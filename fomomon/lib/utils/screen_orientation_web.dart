// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/scheduler.dart';

// Web implementation of screen orientation locking via the browser
// Screen Orientation API (screen.orientation.lock()).
//
// Constraints:
//   - Only works in installed PWA (display: standalone) or fullscreen mode.
//     Called from a plain browser tab, lock() throws NotSupportedError and
//     the orientation is unchanged. Our catch silently swallows this.
//   - Only works on touch devices (Android + Chrome). Desktop browsers ignore
//     orientation lock regardless of display mode.
//   - Requires a recent user gesture in the call chain (satisfied here because
//     the user tapped a site on the map immediately before reaching this screen).
//
// Timing: lock() is fired via addPostFrameCallback rather than directly from
// initState. Calling it from initState was found to have no effect in the
// installed PWA even when the call succeeded without error — the orientation
// did not change. The hypothesis is that the browser needs the Flutter web
// canvas to have rendered at least one frame before it will honour the lock
// from this document context.
//
// Status: postFrameCallback approach deployed but not yet confirmed working.
// See docs/v2/pwa/checkpoints.md for the current debug state.

Future<void> lockScreenOrientation(String mode) async {
  SchedulerBinding.instance.addPostFrameCallback((_) async {
    try {
      await html.window.screen?.orientation?.lock(mode);
    } catch (_) {}
  });
}

void unlockScreenOrientation() {
  try {
    html.window.screen?.orientation?.unlock();
  } catch (_) {}
}
