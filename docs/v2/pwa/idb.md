# Stage 1 — IndexedDB Image Persistence

## Problem

`local_image_storage_web.dart` holds image bytes in a static
`Map<String, Uint8List>`. This map lives in JavaScript heap memory for the
lifetime of the browser tab. Closing the tab, reloading the page, or the OS
killing the PWA in the background destroys it.

Session metadata (portrait/landscape paths, site ID, timestamp) survives in
`SharedPreferences` / `localStorage`, but the image bytes it references are
gone. The session appears in the upload gallery but fails to upload because
there is nothing to read.

On native, images are written to `{docsDir}/images/` and survive restarts.
This stage closes that gap on web.

---

## Solution

Replace the in-memory `Map` with **IndexedDB** — the browser's structured
storage for binary data. IDB:
- Survives tab close, reload, and PWA backgrounding
- Has no practical size limit for JPEG blobs (quota is typically 50–80 % of
  free disk space)
- Is available in all PWA-capable browsers (Chrome, Firefox, Safari 15.4+)

### Key constraint — `readBytes()` must stay synchronous

`LocalImageStorage.readBytes()` is called from synchronous contexts (widget
`build`, `initState`). IDB is entirely async. The solution is a **pre-load
cache**: on app startup, load all IDB entries into the in-memory `Map` before
`runApp()`. `readBytes()` then reads from the Map (sync), backed by IDB for
persistence.

```
App start
  └─ LocalImageStorage.initStorage()
       └─ open IDB database
       └─ read all stored entries into _store (Map)
            └─ runApp()

saveImage(bytes, key)
  ├─ _store[key] = bytes        (instant, sync read available immediately)
  └─ IDB.put(bytes.buffer, key) (async, persists across reloads)

readBytes(path)                 (sync, reads from _store)

deleteImage(path)
  ├─ _store.remove(key)
  └─ IDB.delete(key)            (async)
```

---

## What changes

### Files modified

| File | Change |
|------|--------|
| `lib/services/local_image_storage_web.dart` | Full rewrite: add IDB open/preload in `initStorage()`; write to IDB in `saveImage()`; delete from IDB in `deleteImage()` |
| `lib/services/local_image_storage_native.dart` | Add `static Future<void> initStorage() async {}` no-op |
| `lib/services/local_image_storage.dart` | Update header comment (remove in-memory caveat, add `initStorage` to interface) |
| `lib/main.dart` | Add `await LocalImageStorage.initStorage()` before `runApp()` |

No other files change. The `web_img:` key prefix, the `readBytes()` signature,
`saveImage()`'s return value — all identical to the current implementation.
Call sites are untouched.

### IDB schema

- **Database name**: `fomomon_images`
- **Version**: 1
- **Object store**: `images` (out-of-line keys — key passed separately to `put`)
- **Key**: raw filename string, same as the current Map key (no `web_img:` prefix)
- **Value**: `ArrayBuffer` (stored as `bytes.buffer` from a `Uint8List`)

---

## Ghost image caching

Ghost images (reference overlays) are fetched from S3 via `site_service
._ensureCachedImage()` and stored via `LocalImageStorage.saveImage()`. With IDB
they now persist:

- First visit to a site with a reference image → fetch from S3 → store in IDB
- Subsequent visits (same or future session) → `imageExists()` returns true →
  skip S3 fetch → `readBytes()` returns cached bytes from IDB

This removes the "ghost images require an active internet connection" known gap
from Stage 0.

---

## Fallback

`initStorage()` wraps the IDB open in a try/catch. If IDB is unavailable
(private browsing on Safari, browser flags, etc.), the app falls back silently
to the previous in-memory-only behaviour. Users in private browsing lose images
on reload, but the app does not crash.

---

## Testing checklist

- [ ] Capture portrait + landscape → close the tab → reopen → session still
      shows in upload gallery with visible thumbnails → upload succeeds
- [ ] Capture portrait + landscape → background the PWA (Android home button)
      → return → images still present → upload succeeds
- [ ] Visit a site with a reference ghost image → ghost appears → go offline →
      revisit same site → ghost still appears (cached in IDB)
- [ ] Retake a photo → old image deleted → new photo appears correctly
- [ ] DevTools → Application → IndexedDB → `fomomon_images` → `images` store →
      rows visible after capture
- [ ] Private browsing: app still loads and captures; reload loses images
      (expected — logged to console)
