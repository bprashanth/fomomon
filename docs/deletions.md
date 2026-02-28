# Deletion semantics

## Overview

The app manages three kinds of local data: **site objects** (`local_sites.json`),
**sessions** (`sessions/*.json` + image files), and the **remote sites cache**
(`cache/sites.json`). Each has different deletion rules designed to avoid
data loss while preventing stale data from being used as ghost image candidates
for re-created sites.

---

## Site objects (`local_sites.json`)

Site objects are small (a few hundred bytes of JSON). They are always
**hard-deleted** — the entry is removed from `local_sites.json` immediately.

### When site objects are deleted

| Trigger | Where | What happens |
|---|---|---|
| Site promoted to remote `sites.json` | `SiteSyncService.syncSitesToRemote()` | Hard-deleted from `local_sites.json` after successful `uploadJson`. The site continues to exist in both the remote S3 `sites.json` and the local cache (`cache/sites.json`) that was written in the same operation. |
| Admin deletes site from remote | `SiteService._handleSiteDeletions()` | Hard-deleted from `local_sites.json` when a fresh remote `sites.json` no longer contains the site. |

### Why hard-delete site objects on promotion?

Once a local site graduates into the remote `sites.json`, keeping it in
`local_sites.json` would cause it to be re-synced on every subsequent upload
session. If the admin later deletes the site on the server, the device would
immediately re-add it — a ping-pong. Removing the site object on promotion
breaks this cycle: the next fresh fetch of `sites.json` (at login or on the
home screen) becomes the authoritative source of truth.

---

## Sessions (`sessions/*.json` + image files)

Sessions are larger (JSON + two JPEG files per session). Hard-deleting them on
every site-related event would be lossy and inconsistent. Instead, sessions use
a **soft-delete** flag (`isDeleted`) that is set in the JSON on disk but leaves
the files in place.

### `isDeleted` flag

```dart
// CapturedSession
bool isDeleted;  // default false
```

Persisted in `sessions/{sessionId}.json` as `"isDeleted": true/false`. Old
session files without the key are read as `false` (safe default).

### When sessions are soft-deleted

Sessions are soft-deleted **only** when the remote `sites.json` drops a site
relative to the local cache — i.e., an admin has deleted the site server-side.
This is detected in `SiteService._handleSiteDeletions()`, called from both
`_fetchSitesSynchronously` (prefetch screen / sync fetch) and
`_fetchAndCacheSitesInBackground` (home-screen async refresh).

```
Remote sites.json fetched
        |
        v
cachedIds = IDs in cache/sites.json before overwrite
remoteIds = IDs in fresh remote sites.json
deletedIds = cachedIds − remoteIds   ← admin deleted these
        |
        v
For each deletedId:
  LocalSiteStorage.deleteLocalSite(id)           ← hard delete site object
  LocalSessionStorage.softDeleteSessionsForSite(id)  ← set isDeleted on sessions
```

### When sessions are NOT soft-deleted

Sessions are **not** touched when a local site is promoted to the remote
`sites.json` (the graduation step). The rationale:

- At promotion time, the site's S3 data is fresh and valid — the image URLs in
  those sessions correctly point to objects that were just uploaded.
- Soft deletion for stale URLs is only needed after an admin deletion event,
  which is detected by the sites.json diff on the next fetch, not at upload time.
- Treating promotion specially would create an inconsistency: sessions for
  pre-existing remote sites are never soft-deleted at upload time, only locally-
  originated sites' sessions would be. The diff-based detection applies
  uniformly to all sites.

### Effect of `isDeleted` on ghost image selection

`SiteSyncService._findFirstUploadedSessionForSite()` skips sessions with
`isDeleted = true`. This is the only place the flag is currently checked.

**Why this matters**: ghost image selection picks the *first* uploaded session
for a site and uses its `portraitImageUrl` / `landscapeImageUrl` to populate
`reference_portrait` / `reference_landscape` in the remote `sites.json`. If
those S3 objects have been deleted by the admin (along with the site), using
them would write broken URLs into `sites.json`. The soft-delete flag prevents
this if the site is ever re-created.

### Future hard-delete sweep

Sessions with `isDeleted = true` still occupy disk space. A future sweep can
enumerate all sessions, find those with `isDeleted = true`, and call
`LocalSessionStorage.deleteSession(sessionId)` (which deletes JSON + image
files). This is not implemented today because:

1. Storage impact is low (a few MB at most per device).
2. A hard-delete sweep needs a safe trigger point (e.g., app startup, after
   upload). Doing it incorrectly could delete data that hasn't been uploaded.
3. Soft deletion achieves the correctness goal (ghost image safety) without
   the complexity.

---

## Remote sites cache (`cache/sites.json`)

The cache is always **overwritten** (never deleted) by a fresh remote fetch.
After a successful `syncSitesToRemote()` in `SiteSyncService`, the same data
that was uploaded to S3 is also written to the local cache so the device
immediately reflects the new state without waiting for the next network fetch.

---

## Summary table

| Data | Delete trigger | Delete type | Who does it |
|---|---|---|---|
| Site object in `local_sites.json` | Promoted to remote `sites.json` | Hard | `SiteSyncService` after successful upload |
| Site object in `local_sites.json` | Admin deleted from remote | Hard | `SiteService._handleSiteDeletions` |
| Sessions for a site | Admin deleted site from remote | Soft (`isDeleted = true`) | `SiteService._handleSiteDeletions` → `LocalSessionStorage.softDeleteSessionsForSite` |
| Sessions for a promoted site | Site graduated to remote `sites.json` | **Not deleted** | — |
| `cache/sites.json` | Never explicitly deleted | Overwritten on every fetch / sync | `SiteService`, `SiteSyncService` |
