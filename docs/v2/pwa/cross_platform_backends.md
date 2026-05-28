# Cross-Platform Storage Backends

This document describes the storage architecture introduced in the Stage 0 PWA
migration and updated through Stage 1 (IndexedDB).  The app now compiles and
runs on Android, iOS, and web. Platform-specific code is confined to
`*_native.dart` and `*_web.dart` files selected at compile time via Dart's
conditional export mechanism.

---

## The Conditional Export Pattern

Each storage concern is split into three files:

```
lib/services/local_session_storage.dart         # 2-line conditional export (call-site import)
lib/services/local_session_storage_native.dart  # dart:io implementation (Android/iOS)
lib/services/local_session_storage_web.dart     # SharedPreferences / in-memory (Web)
```

The router file:

```dart
// local_session_storage.dart
export 'local_session_storage_native.dart'
    if (dart.library.html) 'local_session_storage_web.dart';
```

`dart.library.html` is defined only when compiling for the browser.

On native, the compiler sees the `*_native.dart` export; on web, `*_web.dart`.

The selected file's class is the only `LocalSessionStorage` the app ever sees.

```
                  Call site (any screen / service)           
  import '../services/local_session_storage.dart';           
  await LocalSessionStorage.saveSession(session);            
                         |  compile-time selection
           --------------V--------------
           |                           |
   dart.library.html = false    dart.library.html = true
           |                           |
           v                           v
 local_session_storage_native.dart  local_session_storage_web.dart
 (dart:io, path_provider)           (SharedPreferences / localStorage)
```

The same pattern applies to:

- `local_site_storage.dart` / `*_native.dart` / `*_web.dart`
- `local_image_storage.dart` / `*_native.dart` / `*_web.dart`
- `lib/utils/file_bytes.dart` / `file_bytes_io.dart` / `file_bytes_web.dart`

---

## Storage Backends by Data Type

| Aspect          | Native (Android / iOS)                   | Web - Stage 1 (IndexedDB + write-through cache)  |
| --------------- | ---------------------------------------- | ------------------------------------------------ |
| Storage medium  | dart:io File at `{docsDir}/images/{key}` | IndexedDB database `fomomon_images` (persistent) |
| In-memory cache | N/A                                      | `static Map<String, Uint8List> _store = {}`      |
| Lifetime        | Persistent - survives app restarts       | Persistent - survives tab close, reload, PWA bg  |
| Key / path      | Absolute filesystem path                 | `web_img:{filename}` (e.g. `web_img:p.jpg`)      |
| Save            | `File(path).writeAsBytes(bytes)`         | `_store[key] = bytes` + IDB `put(bytes.buffer)`  |
| Read (sync)     | `File(path).readAsBytesSync()`           | `_store[key] ?? Uint8List(0)` (cache hit)        |
| Exists (sync)   | `File(path).existsSync()`                | `_store.containsKey(key)`                        |
| Delete          | `File(path).delete()`                    | `_store.remove(key)` + IDB `delete(key)`         |
| Startup cost    | None                                     | IDB open + cursor preload into `_store`          |

**Write-through cache decision**: IDB is async-only; `readBytes()` must stay synchronous
because it is called from the widget `build` and `initState` methods. The solution is to keep
an in-memory `_store` as the read cache and write every save/delete to both `_store` and
IDB simultaneously. On startup, `initStorage()` opens IDB and loads all entries into
`_store` via a cursor scan - ensuring `readBytes()` is correct even after a reload.
Making `readBytes()` async instead would have required changes at 3+ widget call sites
(`capture_screen initState`, `confirm_screen initState`, upload gallery); the write-through
approach contains all complexity in `local_image_storage_web.dart`.

**Why SharedPreferences cannot store images**: SharedPreferences (localStorage) only
accepts primitive types - String, int, bool, List\<String\>. Storing JPEG bytes as
base64 strings would hit the 5 or 10 MB browser quota almost immediately for even 2-3
photos. IndexedDB handles arbitrary binary blobs.

**`web_img:` key pattern**: The prefix distinguishes web image keys from native filesystem
paths. All image-displaying code calls `LocalImageStorage.readBytes(path)` and passes
the returned bytes to `Image.memory(bytes)` so there are no `Image.file()` calls anywhere.

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
// bytes = Uint8List(...)  from _store lookup (backed by IDB)
Image.memory(bytes, fit: BoxFit.cover)
```

---

### 2. Sessions

| Aspect        | Native                                            | Web                                         |
| ------------- | ------------------------------------------------- | ------------------------------------------- |
| Storage       | dart:io File per session in `{docsDir}/sessions/` | SharedPreferences key `session:{id}`        |
| Index         | Directory listing (`listSync`)                    | SharedPreferences key `session_ids` (JSON)  |
| Persistence   | Permanent (disk)                                  | Permanent (localStorage survives reload)  |
| Image cleanup | Deletes image files by path on delete             | Removes from `_store` + IDB via deleteImage |

Session metadata (siteId, timestamp, responses, upload status, image paths) survives
page reloads on web. With Stage 1, image bytes referenced by `portraitImagePath` /
`landscapeImagePath` also survive reload via IDB, so "upload later" works correctly.

---

### 3. Local Sites

| Aspect      | Native                       | Web                                 |
| ----------- | ---------------------------- | ----------------------------------- |
| Storage     | `{docsDir}/local_sites.json` | SharedPreferences key `local_sites` |
| Format      | `{'sites': [...]}` JSON file | Same JSON string in localStorage    |
| Persistence | Permanent (disk)             | Permanent (localStorage)            |

---

### 4. Sites Cache (`sites.json`)

| Aspect      | Native                       | Web                                 |
| ----------- | ---------------------------- | ----------------------------------- |
| Storage     | `{docsDir}/cache/sites.json` | SharedPreferences key `sites_cache` |
| Persistence | Permanent (disk)             | Permanent (localStorage)            |

The sites cache (from S3) persists across reloads on web. On startup, the app can serve
cached sites immediately and refresh in the background - same async mode as native.

---

### 5. Ghost Reference Images (site overlays)

| Aspect     | Native                                         | Web - Stage 1                                |
| ---------- | ---------------------------------------------- | -------------------------------------------- |
| First load | Download from S3; cache to `{docsDir}/ghosts/` | Fetch from S3; store in IDB via saveImage    |
| Subsequent | Load from local disk (fileExistsAsync)         | Read from `_store` (IDB preloaded at start)  |
| Offline    | Works (disk cache)                             | Works after first load (IDB persistent)      |
| Display    | `Image.memory(readBytes(localPath))`           | `Image.memory(readBytes('web_img:ghost_…'))` |

Ghost images are prefetched eagerly at site-load time in `_fetchSitesSynchronously()`
and refreshed in `_prefetchImagesInBackground()`. With IDB they persist across reloads,
so the ghost overlay works offline after the first session matching native behaviour.

**Known gap**: `_ensureCachedImage()` web branch currently lacks the `imageExists()` check
that the native branch uses (`fileExistsAsync(localPath)`). This means it re-fetches from
S3 on every app launch even when the IDB entry is valid. Fix: add
`LocalImageStorage.imageExists('web_img:$key')` check before the fetch.

---

## Auth Token Storage

`flutter_secure_storage` is conditionally imported with a stub on web:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    if (dart.library.html) '../stubs/flutter_secure_storage_stub.dart';
```

On web, `AuthService` never calls the stub - instead, private helpers `_readKey` /
`_writeKey` / `_deleteKey` branch on `kIsWeb` and use SharedPreferences:

```
kIsWeb = false # FlutterSecureStorage (Keystore / Keychain)
kIsWeb = true  # SharedPreferences (localStorage - unencrypted)
```

The web token is stored unencrypted in localStorage. This is acceptable for
localhost / internal testing. Stage 2 should add Web Crypto API encryption.

