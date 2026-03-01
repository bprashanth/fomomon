# PWA v2 — Implementation Record

This document records what was actually built in Stage 0 of the PWA migration.
It supersedes the design notes in `pwa.md` (which described the intended approach)
with the final decisions and outcomes.

See also:
- `cross_platform_backends.md` — storage backend details and caveats
- `pwa_interfaces.md` — interface contracts for each cross-platform abstraction
- `checkpoints.md` — stage progress and CLI testing instructions

---

## What was built (Stage 0)

The goal of Stage 0 was to get the app compiling and running in Chrome with the
complete capture → upload flow working. No new functionality was added; only the
platform barriers (`dart:io`, `flutter_secure_storage`, compass, `Image.file`) were
removed.

### Compilation strategy: conditional Dart exports

Each `dart:io`-dependent service was split into three files. Callers import only
the router file; the compiler selects native or web implementation automatically.

```
foo_service.dart           ← 2-line export (call site unchanged)
foo_service_native.dart    ← dart:io code
foo_service_web.dart       ← SharedPreferences / in-memory code
```

This avoids runtime `kIsWeb` branching for storage classes; only low-level
infrastructure (`site_service`, `auth_service`, `capture_screen`) uses `kIsWeb`
for logic that cannot be separated by conditional export.

### What changed per file

| File | Change |
|------|--------|
| `pubspec.yaml` | Added `camera_web: ^0.3.2` |
| `local_session_storage.dart` | Replaced with conditional export |
| `local_session_storage_native.dart` | Renamed from original implementation |
| `local_session_storage_web.dart` | New — SharedPreferences (`session:{id}`, `session_ids`) |
| `local_site_storage.dart` | Replaced with conditional export |
| `local_site_storage_native.dart` | Renamed from original implementation |
| `local_site_storage_web.dart` | New — SharedPreferences (`local_sites`) |
| `local_image_storage.dart` | Replaced with conditional export |
| `local_image_storage_native.dart` | Renamed + added `saveImage`, `readBytes`, `imageExists`, `deleteImage` |
| `local_image_storage_web.dart` | New — in-memory `Map<String, Uint8List>` |
| `lib/utils/file_bytes.dart` | New — conditional export for raw I/O |
| `lib/utils/file_bytes_io.dart` | New — dart:io wrappers |
| `lib/utils/file_bytes_web.dart` | New — LocalImageStorage delegation + no-op stubs |
| `lib/stubs/flutter_secure_storage_stub.dart` | New — no-op stub for web conditional import |
| `upload_service.dart` | Removed `dart:io`; uses `readFileBytes` / `fileExists` |
| `site_service.dart` | Removed `dart:io`; kIsWeb branches for cache + ghost images |
| `site_sync_service.dart` | Removed `dart:io`; kIsWeb branches for cache |
| `auth_service.dart` | Removed `dart:io`; conditional import for secure_storage; `_readKey/_writeKey/_deleteKey` helpers |
| `capture_screen.dart` | kIsWeb guard for compass; `xfile.readAsBytes()` + `LocalImageStorage.saveImage`; ghost via `Image.network` on web |
| `home_screen.dart` | kIsWeb guard for FlutterCompass subscription |
| `confirm_screen.dart` | `Image.memory(LocalImageStorage.readBytes(...))` replaces `Image.file` |
| `upload_gallery_item.dart` | `Image.memory(LocalImageStorage.readBytes(...))` replaces `Image.file` |
| `session_detail_dialog.dart` | `Image.memory(LocalImageStorage.readBytes(...))` replaces `Image.file` |

---

## Architecture decisions

### Why in-memory for images (not SharedPreferences or IndexedDB in Stage 0)

- **SharedPreferences** only accepts primitive types (String, bool, int, List\<String\>).
  Storing JPEG bytes as base64 would hit browser localStorage quotas within a few photos.
- **IndexedDB** is the correct long-term solution but requires an additional package
  (`idb_shim` or `sembast_web`) and makes `readBytes` async (currently synchronous).
  Changing the sync/async contract across all callers is a Stage 1 task.
- **In-memory** works for the capture → upload flow within one browser session, which
  is the most common use case. Accepted limitation: reload = image data lost.

### Why `Image.memory` everywhere instead of `Image.file`

`Image.file` requires `dart:io`, which is unavailable on web. Loading bytes via
`LocalImageStorage.readBytes(path)` — synchronous on both platforms — and displaying
with `Image.memory(bytes)` is the universal approach. `readBytes` is fast on both:
- Native: `File(path).readAsBytesSync()` — one disk read, small JPEG
- Web: `_store[key]` — O(1) map lookup

### Why XFile.readAsBytes() instead of File(xfile.path).readAsBytes()

`XFile` is the camera plugin's cross-platform file handle. Its `readAsBytes()` method
works on both native (reads the temp file) and web (returns the in-memory bytes from
the WebRTC capture). Using `File(xfile.path).readAsBytes()` crashes on web because
`xfile.path` is a blob URL, not a filesystem path.

### SocketException portability in auth_service

`on SocketException catch (e)` requires `import 'dart:io'`. Replaced with:
```dart
on Exception catch (e) {
  final msg = e.toString();
  if (msg.contains('SocketException') || msg.contains('Failed to fetch')) {
    throw AuthNetworkException(e);
  }
}
```
`'Failed to fetch'` is the error string produced by the browser's Fetch API when
the network is unreachable.

---

## dart:io confinement

After Stage 0, `import 'dart:io'` appears only in:
- `lib/services/local_session_storage_native.dart`
- `lib/services/local_site_storage_native.dart`
- `lib/services/local_image_storage_native.dart`
- `lib/utils/file_bytes_io.dart`

Verification:
```bash
grep -rn "import 'dart:io'" lib/ | grep -v '_native.dart' | grep -v 'file_bytes_io.dart'
# Expected: no output
```

---

## Known gaps in Stage 0 (by design)

| Gap | Impact | Stage 1 fix |
|-----|--------|-------------|
| Images lost on tab close/reload | Must upload before closing; no "draft sessions" on web | IndexedDB image backend |
| Ghost overlay requires network on web | Overlay blank if offline | Store ghost bytes in IndexedDB after first download |
| Auth token unencrypted in localStorage | Security risk on shared computers | Web Crypto API wrapper |
| Compass heading not captured on web | `reference_heading` is null for all web sessions | Accept as limitation (no fix planned; sensors not available in browser) |

---

## Stage 1 preview

See `checkpoints.md` for the full Stage 1 plan. In brief:

- Replace `local_image_storage_web.dart` with an IndexedDB implementation
- Make `readBytes` async (or pre-load to a memory cache on app init)
- Cache ghost images in IndexedDB on first download
- Encrypt the refresh token with Web Crypto API

---

## Upgrade path from Stage 0 to Stage 1 for images

When the IndexedDB backend is introduced, the `web_img:` key convention is preserved:

```
web_img:{filename}  →  still the path format in CapturedSession.portraitImagePath
```

The only change is that `saveImage` writes to IndexedDB instead of the Map, and
`readBytes` (if made async) reads from IndexedDB. Existing session records in
SharedPreferences with `web_img:` paths will resolve correctly after the upgrade.
