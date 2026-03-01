# Cross-Platform Storage Backends

This document describes the storage architecture introduced in the Stage 0 PWA migration.
The app now compiles and runs on Android, iOS, and web (Chrome / Safari) without any
call-site changes. Platform-specific code is confined to `*_native.dart` and `*_web.dart`
files selected at compile time via Dart's conditional export mechanism.

---

## The Conditional Export Pattern

Each storage concern is split into three files:

```
lib/services/local_session_storage.dart         ← 2-line conditional export (call-site import)
lib/services/local_session_storage_native.dart  ← dart:io implementation (Android / iOS)
lib/services/local_session_storage_web.dart     ← SharedPreferences / in-memory (Web)
```

The router file:

```dart
// local_session_storage.dart
export 'local_session_storage_native.dart'
    if (dart.library.html) 'local_session_storage_web.dart';
```

`dart.library.html` is defined only when compiling for the browser (dart2js / DDC).
On native, the compiler sees the `*_native.dart` export; on web, `*_web.dart`.
The selected file's class is the only `LocalSessionStorage` the app ever sees.

```
┌─────────────────────────────────────────────────────────────┐
│                  Call site (any screen / service)           │
│  import '../services/local_session_storage.dart';           │
│  await LocalSessionStorage.saveSession(session);            │
└────────────────────────┬────────────────────────────────────┘
                         │  compile-time selection
           ┌─────────────┴──────────────┐
           │                            │
   dart.library.html = false    dart.library.html = true
           │                            │
           ▼                            ▼
 local_session_storage_native.dart  local_session_storage_web.dart
 (dart:io, path_provider)           (SharedPreferences / localStorage)
```

The same pattern applies to:
- `local_site_storage.dart` / `*_native.dart` / `*_web.dart`
- `local_image_storage.dart` / `*_native.dart` / `*_web.dart`
- `lib/utils/file_bytes.dart` / `file_bytes_io.dart` / `file_bytes_web.dart`

---

## Storage Backends by Data Type

### 1. Captured Images

| Aspect           | Native (Android / iOS)                      | Web — Stage 0 (in-memory)                    |
|------------------|---------------------------------------------|----------------------------------------------|
| Storage medium   | dart:io File at `{docsDir}/images/{key}`    | `static Map<String, Uint8List> _store = {}`  |
| Lifetime         | Persistent — survives app restarts          | Session-scoped — lost on tab close / reload  |
| Key / path       | Absolute filesystem path                    | `web_img:{filename}` (e.g. `web_img:p.jpg`)  |
| Save             | `File(path).writeAsBytes(bytes)`            | `_store[key] = bytes`                        |
| Read (sync)      | `File(path).readAsBytesSync()`              | `_store[key] ?? Uint8List(0)`                |
| Exists (sync)    | `File(path).existsSync()`                   | `_store.containsKey(key)`                    |
| Delete           | `File(path).delete()`                       | `_store.remove(key)`                         |

**Why SharedPreferences cannot store images**: SharedPreferences (localStorage) only
accepts primitive types — String, int, bool, List\<String\>. Storing JPEG bytes as
base64 strings would hit the 5–10 MB browser quota almost immediately for even 2–3
photos. The in-memory Map bypasses this limit but sacrifices persistence.

**Offline caveat**: On web, images only exist while the browser tab is open. If the
user closes the tab before uploading, image bytes are gone even though the session
record in SharedPreferences survives. Capture → upload must complete in one browser session.

**`web_img:` key pattern**: The prefix distinguishes web image keys from native filesystem
paths. All image-displaying code calls `LocalImageStorage.readBytes(path)` and passes
the returned bytes to `Image.memory(bytes)` — no `Image.file()` anywhere.

```dart
// How the web key flows end-to-end:
// 1. capture_screen.dart after takePicture():
final bytes = await xfile.readAsBytes();
final key = 'portrait_${timestamp.millisecondsSinceEpoch}.jpg';
final path = await LocalImageStorage.saveImage(bytes, key);
// path = 'web_img:portrait_1710000000000.jpg'

// 2. path is stored in CapturedSession.portraitImagePath and persisted to SharedPreferences.

// 3. upload_gallery_item.dart / session_detail_dialog.dart display:
final bytes = LocalImageStorage.readBytes(session.portraitImagePath);
// bytes = Uint8List(...)  from _store lookup
Image.memory(bytes, fit: BoxFit.cover)
```

---

### 2. Sessions

| Aspect        | Native                                           | Web (Stage 0)                              |
|---------------|--------------------------------------------------|--------------------------------------------|
| Storage       | dart:io File per session in `{docsDir}/sessions/`| SharedPreferences key `session:{id}`       |
| Index         | Directory listing (`listSync`)                   | SharedPreferences key `session_ids` (JSON) |
| Persistence   | Permanent (disk)                                 | Permanent (localStorage — survives reload) |
| Image cleanup | Deletes image files by path on delete            | No-op (images already gone or in-memory)   |

Session metadata (siteId, timestamp, responses, upload status, image paths) survives
page reloads on web. However, if images were not uploaded before the page was reloaded,
the `portraitImagePath` / `landscapeImagePath` keys in the session will still reference
`web_img:` paths that no longer exist in memory.

---

### 3. Local Sites

| Aspect      | Native                              | Web (Stage 0)                       |
|-------------|-------------------------------------|-------------------------------------|
| Storage     | `{docsDir}/local_sites.json`        | SharedPreferences key `local_sites` |
| Format      | `{'sites': [...]}` JSON file        | Same JSON string in localStorage    |
| Persistence | Permanent (disk)                    | Permanent (localStorage)            |

---

### 4. Sites Cache (`sites.json`)

| Aspect      | Native                              | Web (Stage 0)                        |
|-------------|-------------------------------------|--------------------------------------|
| Storage     | `{docsDir}/cache/sites.json`        | SharedPreferences key `sites_cache`  |
| Persistence | Permanent (disk)                    | Permanent (localStorage)             |

The sites cache (from S3) persists across reloads on web. On startup, the app can serve
cached sites immediately and refresh in the background — same async mode as native.

---

### 5. Ghost Reference Images (site overlays)

| Aspect      | Native                                  | Web (Stage 0) — ⚠️ ONLINE ONLY         |
|-------------|-----------------------------------------|-----------------------------------------|
| First load  | Download from S3; cache to `{docsDir}/ghosts/` | Return S3 URL directly              |
| Subsequent  | Load from local disk                    | Fetch from S3 each time                 |
| Offline     | Works (disk cache)                      | Fails silently (network required)       |
| Display     | `Image.memory(readBytes(localPath))`    | `Image.network(s3Url)`                  |

`site_service._ensureCachedImage` returns the S3 URL immediately on web:
```dart
if (kIsWeb) return remoteUrl;  // ⚠️ ONLINE-ONLY: no local cache on web
```
This means the ghost image overlay in the capture screen requires an active internet
connection on web. If the browser is offline, the overlay silently fails to display.

---

## `Image.file` → `Image.memory` Migration

On native, image display used to rely on dart:io File paths:
```dart
// BEFORE (native only — crashes on web)
Image.file(File(session.portraitImagePath), fit: BoxFit.cover)
```

On web, `dart:io` is unavailable and paths are `web_img:` keys, not filesystem paths.
The universal replacement is to load bytes synchronously and use `Image.memory`:

```dart
// AFTER (all platforms)
final bytes = LocalImageStorage.readBytes(path);  // sync; Map lookup on web, readAsBytesSync on native
if (bytes.isEmpty) return Icon(Icons.broken_image);
Image.memory(bytes, fit: BoxFit.cover)
```

This pattern is used in:
- `lib/screens/confirm_screen.dart` (full-screen captured image display)
- `lib/screens/capture_screen.dart` (ghost overlay on native)
- `lib/widgets/upload_gallery_item.dart` (session thumbnail)
- `lib/widgets/session_detail_dialog.dart` (portrait + landscape detail)

---

## Auth Token Storage

`flutter_secure_storage` is conditionally imported with a stub on web:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    if (dart.library.html) '../stubs/flutter_secure_storage_stub.dart';
```

On web, `AuthService` never calls the stub — instead, private helpers `_readKey` /
`_writeKey` / `_deleteKey` branch on `kIsWeb` and use SharedPreferences:

```
kIsWeb = false → FlutterSecureStorage (Keystore / Keychain)
kIsWeb = true  → SharedPreferences (localStorage — unencrypted)
```

The web token is stored unencrypted in localStorage. This is acceptable for
localhost / internal testing (Stage 0). Stage 1 should add Web Crypto API encryption.

---

## What Works Offline (Web vs Native)

| Feature                      | Native offline | Web in-memory offline |
|------------------------------|----------------|-----------------------|
| View cached sites             | ✅             | ✅ (SharedPreferences) |
| View previously saved sessions| ✅             | ✅ (metadata only)     |
| View session images           | ✅             | ❌ (in-memory; gone after reload) |
| Capture new photos            | ✅             | ✅ (camera works offline) |
| Use ghost reference overlay   | ✅ (disk cache) | ❌ (requires S3 network) |
| Upload sessions               | ❌ (needs network)| ❌ (needs network)    |

---

## Architecture Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         App Screens / Services                          │
│  capture_screen  confirm_screen  upload_gallery  session_detail_dialog  │
│  site_service    site_sync_service  upload_service  auth_service        │
└──────────┬──────────────────────────────────────────────────────────────┘
           │ import '.../local_image_storage.dart'  (conditional export)
           │ import '.../local_session_storage.dart'
           │ import '.../local_site_storage.dart'
           │ import '.../utils/file_bytes.dart'
           │
           ├──── dart.library.html = false (native build) ────────────────┐
           │                                                               │
           │  LocalImageStorage      → dart:io File in {docsDir}/images/  │
           │  LocalSessionStorage    → dart:io File per session            │
           │  LocalSiteStorage       → dart:io File local_sites.json       │
           │  readFileBytes/fileExists → dart:io File                      │
           │  Auth tokens            → FlutterSecureStorage (Keystore)     │
           │  Sites cache            → dart:io File sites.json             │
           │  Ghost images           → dart:io File in {docsDir}/ghosts/   │
           │  Image display          → LocalImageStorage.readBytes()        │
           │                           → Image.memory(bytes)               │
           └───────────────────────────────────────────────────────────────┘
           │
           └──── dart.library.html = true (web build) ────────────────────┐
                                                                           │
             LocalImageStorage      → Map<String, Uint8List> (in-memory)  │
             LocalSessionStorage    → SharedPreferences (localStorage)     │
             LocalSiteStorage       → SharedPreferences (localStorage)     │
             readFileBytes/fileExists → LocalImageStorage (in-memory)     │
             Auth tokens            → SharedPreferences (localStorage)     │
             Sites cache            → SharedPreferences (localStorage)     │
             Ghost images           → S3 URL via Image.network() ⚠️ONLINE  │
             Image display          → LocalImageStorage.readBytes()         │
                                      → Image.memory(bytes)                │
             ⚠️ Images lost on tab close / reload                          │
             └──────────────────────────────────────────────────────────────┘
```

---

## Stage 1 — IndexedDB Backend

Stage 1 will replace the in-memory image store with an IndexedDB backend, enabling
persistent binary storage in the browser. Changes required:

1. **New file**: `lib/services/local_image_storage_idb.dart`
   - Uses `idb_shim` package (or `sembast_web` with a blob adapter)
   - `saveImage(bytes, key)` → `objectStore.put(bytes, key)` async
   - `readBytes(path)` → will need to become `async` (DB read is async)
   - If `readBytes` must stay sync, pre-load into a memory cache on app start
     and invalidate on save/delete

2. **New conditional export chain**:
   - Option A: Two-tier — native vs web; on web use IDB
   - Option B: Three-tier with a build flag to select Stage-0 web vs Stage-1 web

3. **Ghost images**: `_ensureCachedImage` on web would download once and store in
   IDB by key `ghost:{siteId}:{filename}`, removing the online-only constraint.

4. **Session images**: After reload, `readBytes('web_img:portrait_...')` would hit
   IDB and return the persisted bytes, making "upload later" work on web.

5. **Token encryption**: Wrap the SharedPreferences token store with Web Crypto API
   (AES-GCM) so the refresh token is not in localStorage in plaintext.

---

## File Reference

| File | Role |
|------|------|
| `lib/services/local_image_storage.dart` | Conditional export — image storage router |
| `lib/services/local_image_storage_native.dart` | dart:io implementation |
| `lib/services/local_image_storage_web.dart` | In-memory Map implementation (Stage 0 web) |
| `lib/services/local_session_storage.dart` | Conditional export — session storage router |
| `lib/services/local_session_storage_native.dart` | dart:io implementation |
| `lib/services/local_session_storage_web.dart` | SharedPreferences implementation |
| `lib/services/local_site_storage.dart` | Conditional export — local site storage router |
| `lib/services/local_site_storage_native.dart` | dart:io implementation |
| `lib/services/local_site_storage_web.dart` | SharedPreferences implementation |
| `lib/utils/file_bytes.dart` | Conditional export — raw file I/O router |
| `lib/utils/file_bytes_io.dart` | dart:io implementation |
| `lib/utils/file_bytes_web.dart` | Web stubs / LocalImageStorage delegation |
| `lib/stubs/flutter_secure_storage_stub.dart` | No-op stub enabling conditional import of flutter_secure_storage |
