## Site Sync: Promoting Local Sites To Remote `sites.json`

__Calcualted risk__
```
The main problem with the current sync sites design is if multiple users sync different sites in the same org, it is anybody's guess who will win because we don't "lock". This is typically when a database is introduced in the desing. But for as long as there is only really 1 user per org, or as long as the org can be made single user (i.e. only 1 phone updating sites.json) we will be safe. 
```

This document describes how locally created sites are promoted into the
canonical `sites.json` in S3 so that they persist across devices and app
reinstalls.

See also: `docs/sites.md` for the high-level sites and caching behavior.

### Background

- Remote sites are stored in `sites.json` at:
  - `https://<bucket>.s3.amazonaws.com/<org>/sites.json`
  - For example, `https://fomomon.s3.amazonaws.com/t4gc/sites.json`
- On device:
  - Remote `sites.json` is cached at `{app_documents}/cache/sites.json`.
  - Locally created sites live in `{app_documents}/local_sites.json` via
    `LocalSiteStorage`.
  - Sessions are stored in `{app_documents}/sessions/*.json` via
    `LocalSessionStorage`.
- At runtime, `SiteService.fetchSitesAndPrefetchImages()`:
  - Loads remote sites from cached/network `sites.json`.
  - Loads local sites from `local_sites.json`.
  - Merges them with **remote sites taking precedence** on ID conflicts.

This means a new site created in the field will show up in the app (thanks to
`local_sites.json`), but unless we also update the remote `sites.json`, that
site will **not** exist on other devices or after a reinstall.

### Goal

When uploads complete successfully, sync local sites into the remote
`sites.json` by:

1. Taking any local site that does **not** already exist in remote
   `sites.json`.
2. Finding at least one successfully uploaded session for that site (which
   gives us portrait/landscape image URLs).
3. Creating new site entries in `sites.json` that:
   - Preserve location and survey questions from the local site.
   - Use the uploaded images as `reference_portrait` / `reference_landscape`.
4. Uploading the updated `sites.json` back to S3 without clobbering existing
   sites.

### Data Model Recap

- Sites (`fomomon/lib/models/site.dart`):
  - `id`, `lat`, `lng`
  - `reference_portrait`, `reference_landscape` (relative to `bucket_root`)
  - `bucketRoot` (full `bucket_root` URL)
  - `surveyQuestions`
  - `isLocalSite`

- Sessions (`fomomon/lib/models/captured_session.dart`):
  - `siteId`, `latitude`, `longitude`
  - Local image paths: `portraitImagePath`, `landscapeImagePath`
  - Uploaded URLs: `portraitImageUrl`, `landscapeImageUrl`
  - `timestamp`, `userId`, `responses`, `isUploaded`

### Implementation: `SiteSyncService`

File: `fomomon/lib/services/site_sync_service.dart`

#### Entry Point

- `SiteSyncService.syncSitesToRemote()`:
  - Skips when `AppConfig.isGuestMode` is true (guest sites are hardcoded and
    use a separate public bucket).
  - Loads remote sites and `bucket_root` from the cached
    `{app_documents}/cache/sites.json`, or:
    - Falls back to `AppConfig.getResolvedBucketRoot()` and an empty site list
      if the cache does not exist or is invalid.
  - Loads local sites from `LocalSiteStorage.loadLocalSites()`.
  - Determines which local sites are **not yet present** remotely
    (by `site.id`).
  - Loads all sessions from `LocalSessionStorage.loadAllSessions()` and
    filters to those that:
    - `isUploaded == true`
    - Have non-empty `portraitImageUrl` and `landscapeImageUrl`.
  - For each **new** local site:
    - Finds the first uploaded session for that `siteId`
      (oldest timestamp first).
    - Extracts relative image paths from the uploaded URLs, relative to
      the `bucket_root`.
    - Constructs a new `Site` instance:
      - `id`: from local site.
      - `lat` / `lng`: from local site.
      - `referencePortrait` / `referenceLandscape`: relative paths derived
        from the uploaded URLs.
      - `bucketRoot`: remote `bucket_root`.
      - `surveyQuestions`: copied from the local site.
      - `isLocalSite`: set to `false` (now canonical/remotely defined).
  - Builds the updated `sites.json` structure:
    - `bucket_root`: remote bucket root.
    - `sites`: existing remote sites + new site entries, serialized via
      `Site.toJson()`.
  - Uploads the updated JSON using:
    - `UploadService.uploadJson(updatedData, bucketRoot, 'sites.json')`.

All errors inside `syncSitesToRemote()` are caught and **logged** with a
`site_sync:` prefix; they never throw to the caller.

#### Relative Path Extraction

Uploaded files are stored with full URLs, e.g.:

- `https://fomomon.s3.amazonaws.com/t4gc/testing1/user_ts_portrait.jpg`

Given:

- `bucketRoot = https://fomomon.s3.amazonaws.com/t4gc`

The sync code extracts:

- `testing1/user_ts_portrait.jpg`

This relative path becomes the `reference_portrait` in `sites.json`. The same
logic applies for the landscape image.

If the bucket root cannot be found inside the URL, the site is skipped and a
log line is emitted.

### When Sync Runs

File: `fomomon/lib/widgets/upload_dial_widget.dart`

- After `UploadService.uploadAllSessions()` completes successfully,
  `_onUploadPressed()` now calls:

  ```dart
  await SiteSyncService.syncSitesToRemote();
  ```

- This happens **before** the widget refreshes its local session counts and
  turns off the uploading state, so the entire upload + sync cycle is
  represented as a single “Uploading…” operation in the UI.

### Deduplication Rules

Deduplication is handled in two places:

1. **During sync:**
   - Only local sites whose IDs are **not present** in the remote list are
     promoted into `sites.json`.

2. **During fetch/merge:**
   - `SiteService._mergeSites(remoteSites, localSites)`:
     - Adds all `remoteSites` first, tracking IDs.
     - Adds only those `localSites` whose IDs are not already present.
     - Result: **remote sites take precedence** when there is a conflict.

This ensures:

- Existing remote sites are never clobbered.
- Newly promoted sites appear only once in the merged list:
  - After sync, on the next fetch, those sites will come from `sites.json`
    (remote) and will suppress the local versions with the same ID.

### Error Handling & Logging

- `SiteSyncService.syncSitesToRemote()`:
  - Logs and continues on:
    - Missing or unreadable cache file.
    - No local sites.
    - No uploaded sessions with image URLs.
    - Failure to match a local site to an uploaded session.
    - Failure to extract relative paths from URLs.
    - Failure to upload `sites.json` to S3.
  - All log messages are prefixed with `site_sync:` for easy grepping.
  - Does **not** throw errors up to the UI; upload flow is unaffected.

### Edge Cases

- **No `sites.json` exists in S3**:
  - The cache will be empty or missing.
  - Sync starts with an empty remote list and creates a new `sites.json`
    containing only the new sites.

- **Multiple sessions for the same site**:
  - Sync uses the **oldest** uploaded session (by timestamp) as the source
    of ghost images.

- **Uploaded session JSON present but image uploads failed**:
  - If `portraitImageUrl` / `landscapeImageUrl` are missing or empty, that
    site is skipped for this sync run. On a later successful upload, sync
    can run again and pick up the images.

- **Guest mode**:
  - Sync is skipped entirely when `AppConfig.isGuestMode` is true, since
    guest sites are hardcoded (`guest_sites.dart`) and use a separate public
    bucket (`AppConfig.guestBucket`).


