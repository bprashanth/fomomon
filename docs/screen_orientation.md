# Screen Orientation

## The problem

`SystemChrome.setPreferredOrientations()` — the Flutter API for locking screen
rotation — is a **no-op on web**. The browser has its own Screen Orientation API
(`screen.orientation.lock()`) which works for installed PWAs (`display: standalone`)
and fullscreen documents, but not plain browser tabs.

## The solution — `lib/utils/screen_orientation.dart`

A thin conditional export that routes to the right implementation at compile time:

```
lib/utils/screen_orientation.dart         ← conditional export (2 lines)
lib/utils/screen_orientation_stub.dart    ← native: wraps SystemChrome
lib/utils/screen_orientation_web.dart     ← web: wraps screen.orientation.lock()
```

### API

```dart
Future<void> lockScreenOrientation(String mode)
// mode: 'portrait' | 'landscape'
// Locks the screen. On web, silently swallows errors (e.g. plain browser tab).

void unlockScreenOrientation()
// Releases any lock, allowing free rotation.
```

Call sites use `lockScreenOrientation` directly — no `kIsWeb` branches, no
`SystemChrome` imports in screen files.

## Where orientation is managed

The capture flow has two screens that control orientation:

### `capture_screen.dart — initState`

Locks to the mode required for the current capture step:

```dart
lockScreenOrientation(
  widget.captureMode == 'landscape' ? 'landscape' : 'portrait',
);
```

### `confirm_screen.dart — initState`

Always resets to portrait when the confirm screen appears. This is what causes
the screen to "flip back" after landscape capture — the confirm screen, not the
capture screen's dispose:

```dart
lockScreenOrientation('portrait');
```

### `confirm_screen.dart — _onRetake`

Pre-rotates before popping back to `CaptureScreen`, so the transition is smooth
(screen is already in the right orientation when `CaptureScreen` reappears):

```dart
await lockScreenOrientation(
  args.captureMode == 'landscape' ? 'landscape' : 'portrait',
);
Navigator.of(context).pop();
```

## Full orientation flow

```
Portrait CaptureScreen.initState     → lockScreenOrientation('portrait')
  ↓ user captures portrait photo
ConfirmScreen.initState              → lockScreenOrientation('portrait')  [stays portrait]
  ↓ user taps "Use Photo"
  → pushReplacement to landscape CaptureScreen
Landscape CaptureScreen.initState    → lockScreenOrientation('landscape') [rotates to landscape]
  ↓ user captures landscape photo
ConfirmScreen.initState              → lockScreenOrientation('portrait')  [flips back]
  ↓ user taps "Use Photo" → survey/home

  ↓ user taps "Retake" instead:
_onRetake                            → lockScreenOrientation('landscape') [pre-rotate]
  → Navigator.pop() back to landscape CaptureScreen  [already in landscape]
```

## Native vs web behaviour

| Step | Native (stub) | Web |
|---|---|---|
| `lockScreenOrientation('landscape')` | `SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])` | `screen.orientation.lock('landscape')` |
| `lockScreenOrientation('portrait')` | `SystemChrome.setPreferredOrientations([portraitUp])` | `screen.orientation.lock('portrait')` |
| `unlockScreenOrientation()` | `SystemChrome.setPreferredOrientations([all four])` | `screen.orientation.unlock()` |
| Plain browser tab (web) | n/a | lock() throws → silently swallowed; user must rotate manually |
| Installed PWA (web) | n/a | lock() works correctly |
