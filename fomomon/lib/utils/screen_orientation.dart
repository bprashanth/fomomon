// Cross-platform screen orientation locking.
//
// Native: SystemChrome.setPreferredOrientations() handles this; these
//         functions are no-ops (native callers use SystemChrome directly).
// Web:    SystemChrome.setPreferredOrientations() is a no-op on web.
//         The browser Screen Orientation API (screen.orientation.lock()) is
//         used instead. lock() works for installed PWAs (display: standalone)
//         and fullscreen documents. It silently fails in a plain browser tab.
//
// Interface:
//   lockScreenOrientation(String mode) → Future<void>
//     mode: 'portrait', 'landscape', 'any'
//     Locks the screen to the given orientation. Fails silently if unsupported.
//
//   unlockScreenOrientation() → void
//     Releases any orientation lock, allowing free rotation.
export 'screen_orientation_stub.dart'
    if (dart.library.html) 'screen_orientation_web.dart';
