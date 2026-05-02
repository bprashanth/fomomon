# Permissions

## GPS / Location

### Problem

When the app launched with Location Services globally disabled, `_init()` in
`home_screen.dart` exited early (via `GpsService.ensurePermission()`) and never
started the position stream. There was no recovery path — even after the user
enabled location services, the app remained stuck on the "Acquiring GPS" state
until manually restarted.

### Two failure modes

| `GpsPermissionStatus` | Cause | Settings target |
|---|---|---|
| `servicesDisabled` | Global Location toggle is off (Phone Settings → Privacy → Location Services) | `Geolocator.openLocationSettings()` |
| `permissionDenied` | App-level permission denied or denied-forever | `Geolocator.openAppSettings()` |

Both cases are handled identically from a UX standpoint — the user sees an
overlay with the appropriate message and an "Open Settings" button — but the
deep-link destination differs.

### Recovery flow

`_HomeScreenState` mixes in `WidgetsBindingObserver` and overrides
`didChangeAppLifecycleState`. On every `AppLifecycleState.resumed` event, if
`_positionSubscription == null` (i.e. the stream was never successfully started),
`_init()` is called again:

```
app foregrounded
  → didChangeAppLifecycleState(resumed)
  → _positionSubscription == null? yes
  → _init() runs
  → ensurePermission() still failing? → set _gpsError → overlay stays
  → ensurePermission() passes?        → clear _gpsError → stream starts → UI loads
```

`_positionSubscription` is only assigned at the end of the `_init()` happy path,
so it serves as a reliable proxy for "did init ever complete?". Once the stream
is running, `resumed` events are no-ops.

### Key subtlety

When the user enables Location Services globally and returns to the app:
1. `resumed` fires → `_init()` runs
2. `isLocationServiceEnabled()` → `true`
3. Permission likely still `denied` (never asked, since we bailed before)
4. `requestPermission()` fires immediately — system dialog appears
5. User grants → stream starts → overlay clears

This is expected behavior; two Settings round-trips (global toggle + per-app
permission) are required on first use if the app was opened with location off.

### Files changed (this fix only)

These are the only three files touched by this fix. When porting to another
branch, these are the only files that need to change.

- `lib/services/gps_service.dart` — `ensurePermission()` now returns
  `GpsPermissionStatus` enum instead of `bool`
- `lib/screens/home_screen.dart` — `WidgetsBindingObserver` mixin,
  `_gpsError` state, `didChangeAppLifecycleState` retry, GPS error overlay
- `lib/widgets/permission_error_overlay.dart` — new file; reusable full-screen
  overlay widget (title + message + settings button)

---

## PWA / web considerations

The GPS fix described above ports to the `pwa` branch with one part working
identically and one part requiring web-specific changes.

### What works identically on web

- **`WidgetsBindingObserver` / `resumed`** — Flutter web fires
  `AppLifecycleState.resumed` via the page visibility API when the tab is
  refocused. The retry loop (`_positionSubscription == null` → call `_init()`)
  behaves the same.
- **`GpsPermissionStatus` enum** — `Geolocator.requestPermission()` on web
  triggers the browser's location permission dialog. The enum values map
  correctly.
- **`PermissionErrorOverlay`** — pure Flutter widget, no platform dependency,
  renders identically in a browser.

### What breaks on web

`Geolocator.openLocationSettings()` and `Geolocator.openAppSettings()` are
effectively no-ops on web. There is no programmatic API to deep-link into
browser permission settings. The "Open Settings" button in the overlay would
silently do nothing.

Additionally, `servicesDisabled` never triggers on web — browsers have no
global location services toggle. Permission is always site-level, so only
`permissionDenied` is reachable.

### Suggested fix for the pwa branch

Both issues are handled at the call site in `home_screen.dart` — the overlay
widget itself stays generic. Where the overlay is constructed, branch on
`kIsWeb`:

**Message:** replace "Enable Location in your phone's Settings" with "Click
the lock icon in your browser's address bar to re-enable location access."

**Button:** on web, replace the "Open Settings" / `openLocationSettings()` /
`openAppSettings()` calls with a "Retry" action that re-calls
`GpsService.ensurePermission()` directly. This handles the case where the user
has already unlocked the permission in the browser without leaving the tab.

```dart
// in home_screen.dart, where the overlay is constructed:
title: kIsWeb
    ? 'Location access is required'
    : (_gpsError == GpsPermissionStatus.servicesDisabled
        ? 'Location services are off'
        : 'Location access is required'),
message: kIsWeb
    ? 'Click the lock icon in your browser\'s address bar to re-enable location access, then tap Retry.'
    : (_gpsError == GpsPermissionStatus.servicesDisabled
        ? 'Enable Location in your phone\'s Settings to use FOMO.'
        : 'Grant location permission to FOMO in App Settings.'),
onOpenSettings: kIsWeb
    ? () => _init()   // retry in-place; label should read "Retry" not "Open Settings"
    : () { ... },     // existing native deep-link logic
```

`PermissionErrorOverlay` may need an optional `buttonLabel` parameter (default
`'Open Settings'`) so the web path can render `'Retry'` instead.

### Files to change when porting to pwa branch

- `lib/screens/home_screen.dart` — add `kIsWeb` branches to the overlay
  construction (message, button label, `onOpenSettings` callback)
- `lib/widgets/permission_error_overlay.dart` — add optional `buttonLabel`
  parameter (default `'Open Settings'`)

---

## Camera (follow-up PR)

### Problem

When the user has previously denied camera permission and taps "+", the app
navigates to `capture_screen.dart` and calls `_initCamera()`. The `camera`
plugin's `_controller!.initialize()` throws a `CameraException`. The catch
block shows a snackbar ("Failed to initialize camera. Please try again.") which
auto-dismisses after a few seconds, leaving the user on a black screen with a
spinner forever. `_isCameraReady` never becomes `true`. There is no guidance,
no recovery path, and no way out except the hardware back gesture.

There is no global "camera off" toggle (unlike Location Services), so this is
always an app-level permission denial.

### Stuck-state trigger

```
user taps "+"
  → _launchPipeline() → Navigator.push(CaptureScreen)
  → initState() → _initCamera()
  → _controller!.initialize() throws CameraException (permission denied)
  → catch: snackbar shown, dismissed after ~4s
  → _isCameraReady stays false
  → build() returns black screen + CircularProgressIndicator forever
```

### Suggested fix

The fix follows the same `WidgetsBindingObserver` pattern used for GPS, with
one addition: a secondary "Go Back" action on the overlay.

**Why "Go Back" is needed here but not for GPS:** on the home screen there is
no meaningful back destination — the user is waiting for GPS to start. On the
capture screen the user navigated there deliberately and may decide not to grant
camera permission; they need an explicit escape route rather than relying on the
hardware back gesture.

#### 1. Extend `PermissionErrorOverlay`

Add two new optional parameters to `lib/widgets/permission_error_overlay.dart`:

```dart
final IconData icon;            // currently hardcoded to Icons.location_off
final VoidCallback? onGoBack;   // when non-null, renders a secondary text button
```

When `onGoBack` is provided, render it below the primary "Open Settings" button:

```dart
if (onGoBack != null)
  TextButton(
    onPressed: onGoBack,
    child: const Text('Go back', style: TextStyle(color: Colors.white70)),
  ),
```

Update the existing GPS usage in `home_screen.dart` to pass `icon:
Icons.location_off` explicitly (no behaviour change, just now required).

#### 2. Add permission check + overlay to `_CaptureScreenState`

In `lib/screens/capture_screen.dart`:

- Add `with WidgetsBindingObserver` to `_CaptureScreenState` (currently
  `extends State<CaptureScreen> with SingleTickerProviderStateMixin` — both
  mixins can coexist).
- Add a `bool _cameraPermissionDenied = false` state field.
- In `initState()`: `WidgetsBinding.instance.addObserver(this);`
- In `dispose()`: `WidgetsBinding.instance.removeObserver(this);`
- Add `didChangeAppLifecycleState`: if `resumed && !_isCameraReady`, call
  `_initCamera()` again. This means if the user grants permission in App
  Settings and returns, the camera starts automatically without them needing
  to re-tap "+".
- In the `catch` block of `_initCamera()`, detect a permission denial and set
  `_cameraPermissionDenied = true` instead of showing a snackbar. The
  `camera` plugin throws `CameraException` with `description` containing
  "permission" on both platforms when access is denied; check
  `e.description?.toLowerCase().contains('permission') == true` or use the
  `permission` package to check `Permission.camera.status` explicitly (the
  latter is more reliable).
- In `build()`, when `_cameraPermissionDenied` is true, return `Scaffold` +
  `PermissionErrorOverlay` instead of the black spinner:

```dart
if (_cameraPermissionDenied)
  return Scaffold(
    backgroundColor: Colors.black,
    body: PermissionErrorOverlay(
      icon: Icons.camera_alt_outlined,
      title: 'Camera access is required',
      message: 'Grant camera permission to FOMO in App Settings.',
      onOpenSettings: () => openAppSettings(),  // from permission_handler package
      onGoBack: () => Navigator.of(context).pop(),
    ),
  );
```

#### 3. Dependency

`openAppSettings()` requires the `permission_handler` package
(`pub.dev/packages/permission_handler`). Check `pubspec.yaml` — if it is not
already present, add it. `Geolocator.openAppSettings()` (used for GPS) is a
convenience wrapper around the same underlying call; for camera it is cleaner
to call `openAppSettings()` from `permission_handler` directly since the
`camera` plugin does not expose a settings helper.

#### Files to change

| File | Change |
|---|---|
| `lib/widgets/permission_error_overlay.dart` | Add `icon` and optional `onGoBack` parameters |
| `lib/screens/home_screen.dart` | Pass `icon: Icons.location_off` to overlay (required after above change) |
| `lib/screens/capture_screen.dart` | `WidgetsBindingObserver` mixin, `_cameraPermissionDenied` state, retry on resume, `PermissionErrorOverlay` in build |
| `pubspec.yaml` | Add `permission_handler` if not present |
