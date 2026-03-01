# PWA — Implementation Record

## Document map

| Document | What it covers |
|----------|---------------|
| **This file** | What was built and why; how the pieces fit together; testing steps |
| [`cross_platform_backends.md`](cross_platform_backends.md) | Storage backend details per data type; offline capability table; `kIsWeb` inventory |
| [`pwa_interfaces.md`](pwa_interfaces.md) | Interface contracts and storage key reference for each storage class |
| [`idb.md`](idb.md) | IndexedDB design, write-through cache decision, schema, testing checklist |
| [`checkpoints.md`](checkpoints.md) | Stage status, CLI testing instructions, known issues |
| [`deployment.md`](deployment.md) | Netlify deploy process, PWA installability, update workflow |

---

## Guiding principle

Platform differences are confined to `*_native.dart` / `*_web.dart` file pairs selected
at **compile time** via Dart's conditional export mechanism. Callers import only the
router file (`foo_service.dart`) and are unaware of the platform. `kIsWeb` runtime
checks are reserved for differences that cannot be separated by conditional export:
hardware capabilities (compass, accelerometer) and a small number of filesystem guards.

See [`cross_platform_backends.md`](cross_platform_backends.md) for the complete `kIsWeb`
inventory and the rationale for each remaining check.

---

## Stage 0 — Core PWA (Complete)

**Goal**: Get the app compiling and running on Chrome with the complete capture → upload
flow. No new functionality; only platform barriers removed.

### What changed

| File | Change |
|------|--------|
| `pubspec.yaml` | Added `camera_web: ^0.3.2` (WebRTC camera plugin) |
| `local_session_storage.dart` → conditional export | Native: dart:io files; Web: SharedPreferences |
| `local_site_storage.dart` → conditional export | Same pattern |
| `local_image_storage.dart` → conditional export | Native: dart:io; Web: in-memory Map (Stage 0 only) |
| `lib/utils/file_bytes.dart` → conditional export | Wraps dart:io file ops; no-op stubs on web |
| `lib/stubs/flutter_secure_storage_stub.dart` | Enables conditional import of the real package |
| `upload_service.dart` | `dart:io` removed; uses `readFileBytes` / `fileExists` |
| `site_service.dart` | `dart:io` removed; `kIsWeb` cache branches |
| `site_sync_service.dart` | `dart:io` removed; `kIsWeb` cache branches |
| `auth_service.dart` | `dart:io` removed; `_readKey/_writeKey/_deleteKey` helpers branch on `kIsWeb` |
| `capture_screen.dart` | `kIsWeb` compass guard; `XFile.readAsBytes()`; ghost via `Image.network` on web |
| `home_screen.dart` | `kIsWeb` guard for FlutterCompass subscription |
| `confirm_screen.dart`, `upload_gallery_item.dart`, `session_detail_dialog.dart` | `Image.memory(LocalImageStorage.readBytes(...))` replaces `Image.file` |

### Key decisions made in Stage 0

**Why `Image.memory` everywhere**: `Image.file` requires `dart:io`. Loading bytes via
`LocalImageStorage.readBytes(path)` (synchronous on both platforms) and using
`Image.memory(bytes)` is universal. See `pwa_interfaces.md §1` for the sync contract.

**Why `XFile.readAsBytes()` not `File(xfile.path).readAsBytes()`**: `XFile` is the
camera plugin's cross-platform handle. On web, `xfile.path` is a blob URL, not a
filesystem path; the dart:io `File` call crashes. `XFile.readAsBytes()` works on both.

**Why `SocketException` string-match in auth_service**: `on SocketException` requires
`dart:io`. Replaced with `on Exception catch (e)` checking
`e.toString().contains('SocketException') || e.toString().contains('Failed to fetch')` —
the latter being the browser Fetch API's error string for network unreachable.

**`dart:io` confinement** after Stage 0: only in `*_native.dart` files and `file_bytes_io.dart`.
Verify: `grep -rn "import 'dart:io'" lib/ | grep -v '_native.dart' | grep -v 'file_bytes_io.dart'`
→ no output.

---

## Stage 1 — IndexedDB + Storage Layer Cleanup (Complete)

**Goal**: Make image bytes persistent across tab close and page reload; eliminate `kIsWeb`
from the service layer for JSON cache operations.

### What changed

| File | Change |
|------|--------|
| `local_image_storage_web.dart` | Full rewrite: IndexedDB backend with write-through in-memory cache |
| `local_image_storage_native.dart` | Added `initStorage()` no-op to match web interface |
| `local_image_storage.dart` | Updated comment: IDB backend, `initStorage()` in interface |
| `lib/main.dart` | Added `await LocalImageStorage.initStorage()` before `runApp()` |
| `sites_cache_storage.dart` | New conditional export: sites.json cache router |
| `sites_cache_storage_native.dart` | New: reads/writes `{docsDir}/cache/sites.json` |
| `sites_cache_storage_web.dart` | New: reads/writes SharedPreferences by key |
| `site_service.dart` | Removed `kIsWeb` + SharedPreferences imports; uses `SitesCacheStorage` |
| `site_sync_service.dart` | Removed `kIsWeb`, SharedPreferences, file_bytes imports entirely |

See [`idb.md`](idb.md) for the full IndexedDB design including the write-through cache
decision (why `readBytes()` stays synchronous) and the IDB schema.

### How the storage pieces fit together

```
Startup
  main.dart
    └─ LocalImageStorage.initStorage()
         └─ [web only] open IDB → cursor-scan → preload all bytes into _store Map
              └─ runApp()

Capture flow
  capture_screen: XFile.readAsBytes() → LocalImageStorage.saveImage(bytes, key)
                                              ├─ [native] write to {docsDir}/images/{key}
                                              └─ [web]    _store[key] = bytes
                                                          IDB.put(bytes.buffer, key)

Image display (confirm_screen, upload_gallery, session_detail)
  LocalImageStorage.readBytes(path)
    ├─ [native] File(path).readAsBytesSync()
    └─ [web]    _store[key]  ← synchronous; always populated from IDB on startup

Sites cache
  site_service / site_sync_service → SitesCacheStorage.read/write(key)
    ├─ [native] {docsDir}/cache/sites.json  (both callers share same file)
    └─ [web]    SharedPreferences[key]      (separate keys per caller)
```

### `kIsWeb` count before and after Stage 1

| File | Before | After | Remaining checks |
|------|--------|-------|-----------------|
| `site_service.dart` | 7 | 3 | asset copy (no fs), file:// guard, ghost fetch |
| `site_sync_service.dart` | 2 | 0 | — |
| `auth_service.dart` | 3 | 3 | token r/w helpers (by design — see `cross_platform_backends.md §Auth`) |
| Screens / widgets | 5 | 5 | Hardware: compass, accelerometer, orientation dial |
| `telemetry_service.dart` | 1 | 1 | Platform label string |

---

## Known gaps (current)

| Gap | Impact | Fix |
|-----|--------|-----|
| `_ensureCachedImage` web branch re-fetches S3 on every launch | Ghost images re-downloaded even when cached in IDB | Add `LocalImageStorage.imageExists()` check before fetch |
| Screen orientation not flipping back after landscape capture on web | User must manually rotate phone | Investigate `screen.orientation.unlock()` + event-based approach |
| Auth token unencrypted in localStorage | Low risk for internal deployment; higher risk on shared/public computers | Web Crypto API wrapper around SharedPreferences token keys |
| Compass heading `null` for all web sessions | `reference_heading` not populated | Accept — browser has no magnetometer |

---

## Deploying IDB changes

No configuration beyond a standard Flutter web build is needed. IndexedDB is a
browser-native API accessed via `dart:html` (bundled with the Flutter web SDK) — no
new packages, no `manifest.json` changes, no CSP headers, no service worker changes.

```bash
cd fomomon/fomomon
flutter build web          # outputs to build/web/
git add build/web
git commit -m "Stage 1: IDB image persistence"
git push                   # Netlify picks up and deploys
```

On first load after deploy, `initStorage()` opens the `fomomon_images` IDB database
and creates the `images` object store (version 1 upgrade). Existing sessions in
SharedPreferences from Stage 0 that reference `web_img:` paths will show broken images
because those bytes were never written to IDB — this is expected and consistent with the
Stage 0 behaviour (images were already lost on any tab close).

---

## Testing checklist (Stage 1 additions)

The full Stage 0 flow checklist is in [`checkpoints.md`](checkpoints.md). Additional
checks specific to IDB:

### IDB schema presence

After capturing at least one photo:
- Chrome DevTools → Application → Storage → IndexedDB → `fomomon_images` → `images`
- Rows visible with keys matching `portrait_…` / `landscape_…` / `ghost_…`

### Image persistence across reload

1. Capture portrait + landscape → **do not upload**
2. Close the tab (or press F5)
3. Reopen the app
4. Open the upload gallery → session thumbnails still visible
5. Upload → succeeds

### PWA backgrounding on Android

1. Install the PWA from Chrome → "Add to Home Screen"
2. Capture portrait + landscape
3. Press the Android home button (app backgrounds)
4. Return to the app from the home screen
5. Images still present → upload succeeds

### Ghost image offline (first load must be online)

1. Visit a site with a `referencePortrait` / `referenceLandscape` set
2. Confirm ghost overlay is visible while composing the shot
3. Go offline (toggle airplane mode or DevTools Network → Offline)
4. Reload the app
5. Visit the same site → ghost still visible (served from IDB)

### Private browsing fallback

1. Open the app in a Chrome incognito tab (IDB unavailable)
2. Console shows: `local_image_storage_web: IDB unavailable, using in-memory only`
3. App still loads and captures correctly
4. Reload loses images (expected — logged to console, no crash)

---

## Stage 2 — iOS Deployment (Pending)

No code changes expected. The `*_native.dart` paths used for Android work on iOS
(`dart:io`, `camera`, `flutter_secure_storage`, `flutter_compass` all support iOS).

Work items: Apple Developer provisioning, bundle ID + entitlements, code signing,
`flutter build ipa`, TestFlight distribution, App Store privacy strings in `Info.plist`.
