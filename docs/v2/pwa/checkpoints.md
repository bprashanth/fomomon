# PWA Migration Checkpoints

Tracks the staged migration of fomomon from Android-only Flutter app to a
Progressive Web App that also runs in Chrome / Safari.

---

## Stage overview

| Stage | Description | Status |
|-------|-------------|--------|
| **Stage 0** | Compilation + runtime fixes; core flow verified; deployed to Netlify | ✅ Complete |
| **Stage 1** | IndexedDB image persistence + storage layer cleanup | 🔄 Deployed, under testing |
| **Stage 2** | iOS deployment (no new code expected) | ⬜ Pending |

---

## Stage 0 — Core PWA (Complete)

### What was done

| Change | Files |
|--------|-------|
| Added `camera_web: ^0.3.2` (WebRTC camera plugin) | `pubspec.yaml` |
| Conditional image storage (in-memory on web) | `local_image_storage.dart` + `*_native.dart` + `*_web.dart` |
| Conditional session storage (SharedPreferences on web) | `local_session_storage.dart` + `*_native.dart` + `*_web.dart` |
| Conditional local site storage (SharedPreferences on web) | `local_site_storage.dart` + `*_native.dart` + `*_web.dart` |
| Cross-platform file I/O utility | `lib/utils/file_bytes.dart` + `file_bytes_io.dart` + `file_bytes_web.dart` |
| Removed `dart:io` from upload_service | `upload_service.dart` |
| Removed `dart:io` / `path_provider` from site_service; kIsWeb cache branches | `site_service.dart` |
| Removed `dart:io` / `path_provider` from site_sync_service | `site_sync_service.dart` |
| Removed `dart:io` from auth_service; SharedPreferences fallback for tokens | `auth_service.dart` |
| Removed `dart:io` from capture_screen; kIsWeb compass guard; XFile.readAsBytes | `capture_screen.dart` |
| kIsWeb guard for FlutterCompass in home_screen | `home_screen.dart` |
| `Image.memory` everywhere (removed `Image.file`) | `confirm_screen.dart`, `upload_gallery_item.dart`, `session_detail_dialog.dart`, `capture_screen.dart` |

### Known gaps (by design in Stage 0)

- Ghost reference images require an active internet connection on web (no local cache)
- Images lost on page reload — must capture and upload in one browser session
- Auth token in localStorage (unencrypted) — acceptable for localhost
- Compass heading overlay disabled on web — no magnetometer in browser

### Known issues (to fix)

- **Screen orientation not flipping back after landscape capture on web**: The confirm
  screen calls `lockScreenOrientation('portrait')` which calls `screen.orientation.lock('portrait')`,
  but Chrome may not honour this when the installed PWA is not in fullscreen mode.
  The screen stays in landscape after the second capture. Investigate whether
  `screen.orientation.unlock()` followed by a delayed `lock('portrait')` resolves it,
  or whether a `ResizeObserver` / `orientationchange` event approach is needed.

---

## Stage 0 — Testing Instructions

### Prerequisites

```bash
cd fomomon/fomomon
flutter --version   # 3.x required; ensure web support is enabled
flutter config --enable-web
```

### Build verification

```bash
# Confirm zero compilation errors
flutter build web

# Check that dart:io is only in *_native.dart and file_bytes_io.dart
grep -rn "import 'dart:io'" lib/ | grep -v '_native.dart' | grep -v 'file_bytes_io.dart'
# Expected: no output (empty)
```

### Run on localhost

```bash
# Default port 8080
flutter run -d chrome

# Specify a port if needed
flutter run -d chrome --web-port=8080

# For a release-mode build served locally:
flutter build web && cd build/web && python3 -m http.server 8080
# Then open http://localhost:8080 in Chrome
```

### Core flow verification checklist

Run through these in order after launching in Chrome:

- [ ] **App loads**: No JS console errors on startup (`F12` → Console tab)
- [ ] **Login**: Enter credentials → Cognito authentication succeeds → site list appears
- [ ] **GPS**: Browser prompts for location permission → allow → location marker appears on map
- [ ] **Site selection**: Tap a site on the map → capture flow starts
- [ ] **Camera**: Browser prompts for camera permission → allow → portrait camera view opens
- [ ] **Portrait capture**: Take portrait photo → confirm screen shows `Image.memory`
- [ ] **Landscape capture**: Confirm portrait → landscape camera opens → take photo
- [ ] **Survey** (if configured): Answer survey questions
- [ ] **Session saved**: Session appears in the upload gallery
- [ ] **Upload**: Tap upload → both image files appear in S3 bucket → telemetry event fires
- [ ] **Ghost overlay** (if site has reference images): Ghost image visible while composing shot (requires network)
- [ ] **Guest mode**: Set `AppConfig.isGuestMode = true` in code → map loads without login

### Expected limitations (do not file as bugs for Stage 0)

- Compass dial and heading: not shown on web (kIsWeb guard is working correctly)
- Page reload mid-flow: session metadata in localStorage, images gone — user must start over
- Ghost overlay offline: overlay is blank if network disconnects between site load and capture

### S3 verification

After a successful upload, confirm in the AWS console (or `aws s3 ls`):

```
s3://{bucket}/{org}/sessions/{userId}_{timestamp}.json
s3://{bucket}/{org}/images/{siteId}/portrait_{userId}_{timestamp}.jpg
s3://{bucket}/{org}/images/{siteId}/landscape_{userId}_{timestamp}.jpg
s3://{bucket}/{org}/telemetry/{date}/{userId}_{epoch}.json
```

---

## Stage 1 — IndexedDB + Storage Layer Cleanup (Deployed, under testing)

### What was done

| Change | Files |
|--------|-------|
| IndexedDB backend with write-through in-memory cache | `local_image_storage_web.dart` (full rewrite) |
| `initStorage()` no-op on native to match web interface | `local_image_storage_native.dart` |
| Call `initStorage()` before `runApp()` | `lib/main.dart` |
| `SitesCacheStorage` conditional export (eliminates `kIsWeb` from site services) | `sites_cache_storage.dart` + `*_native.dart` + `*_web.dart` |
| Removed `kIsWeb` + SharedPreferences from site_service cache methods | `site_service.dart` |
| Removed `kIsWeb`, SharedPreferences, file_bytes imports entirely | `site_sync_service.dart` |

See [`idb.md`](idb.md) for the full design and [`pwa_design.md`](pwa_design.md) for the testing checklist.

### Testing status

- [ ] Capture → close tab → reopen → thumbnails still visible → upload succeeds
- [ ] PWA backgrounded on Android → return → images still present
- [ ] Ghost overlay visible offline after first load
- [ ] DevTools → Application → IndexedDB → `fomomon_images` → rows visible after capture

### Known gaps remaining after Stage 1

- `_ensureCachedImage` web branch re-fetches S3 on every launch (missing `imageExists()` check)
- Auth token unencrypted in localStorage

---

## Screen orientation (unresolved)

Tracking separately because it cuts across Stage 0 and Stage 1 and is still being debugged.

### Problem

Landscape capture screen does not rotate to landscape on web (installed PWA on Android).
Native is unaffected — `SystemChrome.setPreferredOrientations()` works at OS level
with no display-mode constraint.

### Root cause (confirmed)

`screen.orientation.lock()` requires the page to be in fullscreen or standalone PWA
display mode. Called from a regular browser tab it always throws `NotSupportedError`
(silently swallowed). Confirmed testing environment is the installed PWA (standalone
mode), so this constraint should be satisfied.

### Attempts so far

| Attempt | Outcome |
|---------|---------|
| Call `lock()` directly from `initState` | No effect, no error |
| Move call to `SchedulerBinding.addPostFrameCallback` | Deployed, not yet confirmed working |

### Next debug steps

If `addPostFrameCallback` also has no effect:
1. Add alert before and inside the callback to confirm (a) function is called, (b) callback fires, (c) error text if lock() throws
2. If callback fires and lock() succeeds but screen doesn't rotate: try `Future.delayed(const Duration(milliseconds: 300), ...)` — some Chrome versions need a brief pause after navigation before honouring orientation lock
3. If `screen.orientation` is null: the PWA manifest may need `"orientation": "any"` removed, or the device OS may have orientation locked at system level

---

## Stage 2 — iOS Deployment (Pending)

No code changes expected. The same `*_native.dart` code paths used for Android work
on iOS. Main work items:

- Apple Developer account provisioning
- Bundle ID, entitlements, and code signing configuration
- `flutter build ipa` and TestFlight distribution
- App Store review for camera + location permissions (privacy strings in `Info.plist`)
