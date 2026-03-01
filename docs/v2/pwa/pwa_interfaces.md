# PWA Cross-Platform Interfaces

This document describes the interface contracts for each cross-platform storage
abstraction. Each interface is enforced implicitly — there is no Dart `abstract class`
or `interface` keyword used; instead, both `*_native.dart` and `*_web.dart`
implementations must expose identical static APIs. The compiler selects the
implementation at build time via the conditional export in the router file.

If you add a new method to either backend, you must add it to both backends and
update the call-map in the router file's block comment.

---

## 1. LocalImageStorage

**Router file**: `lib/services/local_image_storage.dart`
**Native backend**: `lib/services/local_image_storage_native.dart` (dart:io)
**Web backend**: `lib/services/local_image_storage_web.dart` (in-memory Map)

### Interface

```dart
class LocalImageStorage {

  /// Saves [bytes] to storage under [key].
  /// Returns an opaque path/key that all other methods accept.
  ///   - Native: writes to {docsDir}/images/{key}; returns the absolute path.
  ///   - Web:    stores in _store[key]; returns 'web_img:{key}'.
  static Future<String> saveImage(Uint8List bytes, String key);

  /// Legacy entry point used by confirm_screen.
  /// If [tempPath] is already in the permanent location (native) or is already
  /// a 'web_img:' key (web), returns it unchanged. Otherwise copies on native.
  static Future<String> saveImageToPermanentLocation({
    required String tempPath,
    required String userId,
    required String siteId,
    required String captureMode,
    required DateTime timestamp,
  });

  /// Returns the raw bytes for the image at [path].
  /// Returns Uint8List(0) if not found.
  /// SYNCHRONOUS — safe to call in initState and build().
  ///   - Native: File(path).readAsBytesSync()
  ///   - Web:    _store[key] ?? Uint8List(0)
  static Uint8List readBytes(String path);

  /// Returns true if an image exists at [path].
  /// SYNCHRONOUS.
  ///   - Native: File(path).existsSync()
  ///   - Web:    _store.containsKey(key)
  static bool imageExists(String path);

  /// Deletes the image at [path].
  ///   - Native: File(path).delete() if exists
  ///   - Web:    _store.remove(key)
  static Future<void> deleteImage(String path);
}
```

### Notes

- `readBytes` must remain synchronous until Stage 1. The synchronous contract is
  relied upon in `initState` (confirm_screen, capture_screen) and in `_buildImage`
  (session_detail_dialog) where async is not possible without a FutureBuilder.
- Stage 1 will introduce `readBytesAsync(path)` backed by IndexedDB, and widgets
  will migrate to FutureBuilder or a pre-loaded bytes approach.

---

## 2. LocalSessionStorage

**Router file**: `lib/services/local_session_storage.dart`
**Native backend**: `lib/services/local_session_storage_native.dart` (dart:io)
**Web backend**: `lib/services/local_session_storage_web.dart` (SharedPreferences)

### Interface

```dart
class LocalSessionStorage {

  /// Persists [session] to storage.
  /// Overwrites any existing session with the same sessionId.
  static Future<void> saveSession(CapturedSession session);

  /// Returns all stored sessions (excluding hard-deleted ones, if applicable).
  /// Order is not guaranteed.
  static Future<List<CapturedSession>> loadAllSessions();

  /// Removes the session with [sessionId] from storage.
  /// Also removes associated image files on native; no-op for images on web
  /// (in-memory images are not reachable from a sessionId after reload).
  static Future<void> deleteSession(String sessionId);

  /// Marks all sessions for [siteId] as soft-deleted (isDeleted = true).
  /// Used when a site is removed from the remote sites.json.
  static Future<void> softDeleteSessionsForSite(String siteId);

  /// Updates [session] in storage to mark it as uploaded.
  /// Sets session.isUploaded = true and persists.
  static Future<void> markUploadedWithUrls(CapturedSession session);

  /// Creates a minimal Site object for [session] using available response data.
  /// Used when the remote site is no longer available.
  /// This is a pure function — no I/O — same on all backends.
  static Site createSiteForSession(CapturedSession session, Site fallbackSite);
}
```

### Storage keys (web backend)

| Key | Type | Content |
|-----|------|---------|
| `session:{sessionId}` | String | JSON-encoded `CapturedSession.toJson()` |
| `session_ids` | String | JSON-encoded `List<String>` of known session IDs |

### Offline behaviour

- Native: sessions on disk survive app restarts.
- Web: session metadata (including `portraitImagePath` / `landscapeImagePath`) survives
  page reloads in localStorage. However, the image bytes those paths reference are in
  the in-memory store, which is cleared on reload. Sessions show as "broken images"
  after reload if not yet uploaded.

---

## 3. LocalSiteStorage

**Router file**: `lib/services/local_site_storage.dart`
**Native backend**: `lib/services/local_site_storage_native.dart` (dart:io)
**Web backend**: `lib/services/local_site_storage_web.dart` (SharedPreferences)

### Interface

```dart
class LocalSiteStorage {

  /// Returns all locally-added sites.
  /// Returns [] if none exist or on read error.
  static Future<List<Site>> loadLocalSites();

  /// Saves or updates [site] in local storage.
  /// If a site with site.id already exists, it is replaced.
  static Future<void> saveLocalSite(Site site);

  /// Removes the site with [siteId] from local storage.
  static Future<void> deleteLocalSite(String siteId);
}
```

### Storage keys (web backend)

| Key | Type | Content |
|-----|------|---------|
| `local_sites` | String | JSON-encoded `{'sites': [site.toJson(), ...]}` |

---

## 4. File I/O Utilities (lib/utils/file_bytes)

**Router file**: `lib/utils/file_bytes.dart`
**Native backend**: `lib/utils/file_bytes_io.dart` (dart:io + path_provider)
**Web backend**: `lib/utils/file_bytes_web.dart` (LocalImageStorage + no-op stubs)

### Interface

```dart
/// Read raw bytes from [path].
/// Native: File(path).readAsBytes()
/// Web:    LocalImageStorage.readBytes(path)  — the in-memory store
Future<Uint8List> readFileBytes(String path);

/// Returns true if a file/image exists at [path]. SYNCHRONOUS.
/// Native: File(path).existsSync()
/// Web:    LocalImageStorage.imageExists(path)
bool fileExists(String path);

/// Async variant of fileExists.
/// Native: File(path).exists()
/// Web:    LocalImageStorage.imageExists(path)
Future<bool> fileExistsAsync(String path);

/// Read text content from [path].
/// Native: File(path).readAsString()
/// Web:    '' (no filesystem; callers use SharedPreferences for text)
Future<String> readFileString(String path);

/// Write [bytes] to [path].
/// Native: File(path).writeAsBytes(bytes)
/// Web:    no-op (use LocalImageStorage.saveImage for images instead)
Future<void> writeFileBytes(String path, List<int> bytes);

/// Write [content] string to [path].
/// Native: File(path).writeAsString(content)
/// Web:    no-op (callers use SharedPreferences for text caches)
Future<void> writeFileString(String path, String content);

/// Ensure [path] directory exists. Creates parent directories.
/// Native: Directory(path).create(recursive: true)
/// Web:    no-op
Future<void> ensureDirectory(String path);

/// Returns the application documents directory path.
/// Native: (await getApplicationDocumentsDirectory()).path
/// Web:    '' (no docs directory on web)
Future<String> getDocsDirPath();
```

### Why write / directory functions are no-ops on web

`site_service` and `site_sync_service` write JSON caches to disk on native.
On web, those same functions use `kIsWeb` branches that write to SharedPreferences
instead of calling `writeFileString`. The web backend's no-op stubs are safety nets
that prevent crashes if a caller misses its `kIsWeb` guard; they do not replace the
SharedPreferences writes.

---

## 5. Auth Token Storage (inside AuthService)

**File**: `lib/services/auth_service.dart`
**Native**: FlutterSecureStorage (conditionally imported)
**Web**: SharedPreferences (localStorage)

### Interface (private helpers inside AuthService)

```dart
// Select backend at runtime using kIsWeb
Future<String?> _readKey(String key);
Future<void>    _writeKey(String key, String value);
Future<void>    _deleteKey(String key);
```

### Storage keys

| Key | Content |
|-----|---------|
| `cognito_refresh_token` | Cognito refresh token string |
| `cognito_username` | User email |
| `cognito_org` | Organisation name from AppConfig |

### Conditional import pattern for flutter_secure_storage

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    if (dart.library.html) '../stubs/flutter_secure_storage_stub.dart';
```

On web the stub is imported, but the `FlutterSecureStorage` instance is never called
(all three helper methods branch on `kIsWeb` and use SharedPreferences). The stub
exists solely to allow the class declaration in auth_service.dart to compile on web
without a `dart:io` error from the real package.

### Stub contract (`lib/stubs/flutter_secure_storage_stub.dart`)

```dart
class FlutterSecureStorage {
  const FlutterSecureStorage();
  Future<String?> read({required String key}) async => null;
  Future<void> write({required String key, required String value}) async {}
  Future<void> delete({required String key}) async {}
}
```

The stub must keep the same API surface as the real `FlutterSecureStorage` for the
compile to succeed. If the real package adds a new method that auth_service calls,
add it to the stub.

---

## Adding a new backend method — checklist

When adding a new method to any storage class:

1. Add the method to `*_native.dart`.
2. Add the same method to `*_web.dart` (with appropriate web semantics or a no-op).
3. Update the `/// Interface` block comment in the router file (`*.dart`).
4. Update the **Migration call-map** in the router file's block comment.
5. Update this document (pwa_interfaces.md) under the relevant interface section.
6. If the method is async on web but sync on native (e.g. due to IndexedDB), coordinate
   with all call sites to handle the async contract.
