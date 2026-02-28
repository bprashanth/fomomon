# Observability

## Background: why not print statements

Print statements stay on the phone. Logcat is only readable via USB debugging
or on rooted devices — the device has to be in front of you. In production
field use there is no ADB.

Firebase Crashlytics / Sentry would solve crash reporting and analytics, but
they add third-party SDKs and move data outside AWS. CloudWatch Logs adds
operational cost and a Lambda endpoint to maintain.

## What we built instead: S3 telemetry

A lightweight, offline-buffered telemetry layer is implemented in the Flutter
app (branch `monitoring`). Events are buffered locally in `shared_preferences`
and flushed to S3 as a single JSON file once per upload session — piggybacking
on the existing upload flow. No new AWS services, no third-party SDKs.

### Debug-only logging (`dLog`)

All `print()` calls in service files are replaced with `dLog()`:

```dart
// lib/utils/log.dart
import 'package:flutter/foundation.dart';

// ignore: avoid_print
void dLog(String message) {
  if (kDebugMode) print(message);
}
```

`kDebugMode` is a compile-time constant so `dLog` is completely tree-shaken
from release builds. No logcat exposure in production.

---

## Architecture

```
[App pivot point: error or success event]
        |
        v
TelemetryService.log(level, TelemetryPivot.xxx, message, {error, context})
  checks AppConfig.isTelemetryEnabled → no-op if false
        |
        v
TelemetryStorage.appendEvent(event)
  shared_preferences key "telemetry_buffer"
  JSON-encoded list, max 200 events (FIFO ring buffer)
        |
        v
[When online — piggybacked on UploadService.uploadAllSessions()]
        |
        v
TelemetryService.flush(userId, org, platform)
        |
        v
TelemetryStorage.loadAndClear()  ← drain and wipe queue
        |
        v
S3 PUT  fomomon/telemetry/{org}/{YYYY-MM-DD}/{userId}_{epochMs}.json
(presigned URL via S3SignerService — same signing path as session uploads)
```

**Key files in `fomomon/` (the Flutter app):**

| File | Role |
|---|---|
| `lib/services/telemetry_service.dart` | Singleton: `log()` buffers, `flush()` uploads |
| `lib/services/telemetry_storage.dart` | `shared_preferences` wrapper, 200-event FIFO |
| `lib/models/telemetry_event.dart` | `TelemetryEvent` value object + `TelemetryLevel` enum |
| `lib/models/telemetry_pivots.dart` | All pivot name constants (canonical source of truth) |
| `lib/utils/log.dart` | `dLog()` — debug-only print wrapper |
| `lib/config/app_config.dart` | `isTelemetryEnabled` flag |

---

## Event schema

Each flush writes one JSON file:

```json
{
  "appVersion": "1.1.0",
  "platform": "android",
  "userId": "john_doe",
  "org": "t4gc",
  "flushedAt": "2024-01-15T10:30:00Z",
  "events": [
    {
      "timestamp": "2024-01-15T10:28:00Z",
      "level": "error",
      "pivot": "session_upload_failed",
      "message": "Session upload failed for site_001",
      "error": "AuthSessionExpiredException: token expired",
      "context": { "siteId": "site_001", "sessionId": "john_doe_2024-01-15T..." }
    },
    {
      "timestamp": "2024-01-15T10:29:00Z",
      "level": "info",
      "pivot": "session_uploaded",
      "message": "Session uploaded from site_001",
      "error": null,
      "context": { "siteId": "site_001", "sessionId": "john_doe_2024-01-15T..." }
    }
  ]
}
```

**`level`** values: `info`, `warning`, `error`

---

## Pivot points (in app lifecycle order)

All pivot names are constants in `lib/models/telemetry_pivots.dart`. Every
`TelemetryService.log()` call site must use a `TelemetryPivot.` constant;
never pass an inline string.

| Dart constant | String value | Level | Meaning | Where logged |
|---|---|---|---|---|
| `authConfigFetchFailed` | `auth_config_fetch_failed` | error | `fetchAuthConfig()` failed at startup; app cannot log in | `login_screen.dart` |
| `loginFailed` | `login_failed` | error | `login()` failed (wrong credentials, network, Cognito) | `login_screen.dart` |
| `siteFetchFailed` | `site_fetch_failed` | error | `sites.json` could not be fetched from S3 | `site_service.dart` |
| `siteFetchCacheFallback` | `site_fetch_cache_fallback` | warning | Network fetch failed; using cached `sites.json` (possibly stale) | `site_service.dart` |
| `sitesUpdated` | `sites_updated` | info/warning | Remote `sites.json` and local cache have diverged. `warning` when local-only sites exist (not in remote); `info` when only new remote sites appear. context: `{newSiteIds: [...], localOnlySiteIds: [...], totalRemote: n, totalLocal: n}` | `site_service.dart` |
| `referenceImageFetchFailed` | `reference_image_fetch_failed` | warning | Ghost reference image could not be downloaded (HTTP error or network failure); site shows no overlay during capture. context: `{siteId, orientation, remoteUrl, statusCode}` | `site_service.dart` |
| `gpsPermissionDenied` | `gps_permission_denied` | warning | Location service disabled or permission denied | `gps_service.dart` |
| `sessionCaptured` | `session_captured` | info | Session saved at end of capture pipeline | `survey_screen.dart` |
| `tokenRefreshFailed` | `token_refresh_failed` | warning | Cognito session expired and could not be refreshed before upload | `upload_service.dart` |
| `sessionUploadFailed` | `session_upload_failed` | error | A single session failed to upload; remains in local queue | `upload_service.dart` |
| `sessionUploaded` | `session_uploaded` | info | A single session successfully uploaded to S3 | `upload_service.dart` |
| `siteSyncFailed` | `site_sync_failed` | error | `syncSitesToRemote()` could not write updated `sites.json` | `site_sync_service.dart` |
| `siteSynced` | `site_synced` | info | A locally created site written to remote `sites.json` | `site_sync_service.dart` |

---

## How to add a new pivot point

**Step 1** — declare the constant in `lib/models/telemetry_pivots.dart`, in
the correct lifecycle section:

```dart
/// Short description of when this fires and what it means.
/// Logged from: which_file.dart
static const String myEventName = 'my_event_name';  // follows naming convention
```

Naming rules:
- Errors → `{domain}_{action}_failed` (e.g. `site_fetch_failed`)
- Warnings → descriptive phrase (e.g. `gps_permission_denied`)
- Info → past-tense verb (e.g. `session_uploaded`)

**Step 2** — call `TelemetryService.instance.log()` at the pivot, always using
the constant:

```dart
// Error — operation failed
TelemetryService.instance.log(
  TelemetryLevel.error,
  TelemetryPivot.myEventName,
  'Human-readable description, include key identifiers',
  error: e,                        // the caught exception
  context: {'siteId': site.id},   // any structured fields useful for filtering
);

// Warning — degraded but continuing
TelemetryService.instance.log(
  TelemetryLevel.warning,
  TelemetryPivot.siteFetchCacheFallback,
  'Fell back to cached sites.json (${n} sites)',
);

// Info — success
TelemetryService.instance.log(
  TelemetryLevel.info,
  TelemetryPivot.sessionCaptured,
  'Session saved for ${site.id}',
  context: {'siteId': site.id, 'sessionId': session.sessionId},
);
```

Rules:
- Place calls in existing `catch` blocks or clearly identified failure/success
  paths — never in loops or per-frame callbacks.
- `log()` is fire-and-forget and never throws; no additional try/catch needed.
- The flush happens automatically at the end of `UploadService.uploadAllSessions()`.

**Step 3** — add the pivot to the reference table above.

---

## S3 rotation policy

### Path structure: `telemetry/{org}/` not `{org}/telemetry/`

The telemetry S3 key is:

```
{bucket}/telemetry/{org}/{YYYY-MM-DD}/{userId}_{epochMs}.json
```

Example: `fomomon/telemetry/t4gc/2024-01-15/john_doe_1705312680000.json`

**Why top-level `telemetry/` instead of nesting under the org prefix?**

Telemetry files are ephemeral diagnostic data. The org prefix (`{org}/`) holds
long-term, sensitive field data: `sites.json`, `users.json`, and captured
images. These must never expire. An S3 lifecycle rule that accidentally covers
`{org}/` would silently delete production data.

By hoisting telemetry out to a separate top-level prefix:

1. **Single lifecycle rule covers all orgs.** S3 prefix filters are literal
   strings with no wildcard support. `*/telemetry/` is not valid S3 syntax.
   With `{org}/telemetry/` paths, a separate per-org rule would be required
   forever. With `telemetry/` as the root, one rule handles every org now and
   in the future.

2. **Zero blast-radius for expiry.** The lifecycle rule is scoped to
   `telemetry/` only — it cannot reach `{org}/sites.json`,
   `{org}/users.json`, or captured images regardless of misconfiguration.

3. **Clean separation of concerns.** Long-term field data lives under `{org}/`.
   Ephemeral diagnostics live under `telemetry/`. The bucket structure makes
   the retention intent obvious.

### Lifecycle rule

One rule on the `fomomon` bucket covers all current and future orgs:

- **Prefix**: `telemetry/`
- **Action**: Expire current versions after **90 days**

This rule is set automatically by the admin panel's "Use Org" action (see
Phase 1.5 below). It is idempotent — if the rule already exists it is not
re-added. Implementation: `s3_service.py:ensure_telemetry_lifecycle_rule()`.

**Cost without the rule:** ~3 MB/month at 100 events/day × 1 KB — essentially
$0. The rule is hygiene, not a cost emergency.

---

## Phase 1.5: Admin panel — org provisioning and log viewer

**Repo**: `admin/` (this repo)
**Status**: implemented

The existing admin panel (`admin/backend/main.py` + `admin/frontend/`) already
manages users and `sites.json` per org. Phase 1.5 extended it with two features:

### Feature A: Org provisioning on "Use Org"

The existing **"Use Org"** button now calls `POST /api/orgs/{org}/provision`
before refreshing the UI. This is idempotent — safe to call on every selection,
whether the org is new or already exists.

**Backend** — `POST /api/orgs/{org}/provision` (`admin/backend/main.py`):

1. `s3.ensure_org_prefix(org)` — creates `{org}/` placeholder.
2. `s3.ensure_telemetry_prefix(org)` — creates `telemetry/{org}/` placeholder.
3. `s3.ensure_telemetry_lifecycle_rule()` — idempotently adds the single
   `telemetry/` lifecycle rule (90-day expiry) if not already present.
4. Returns `{ ok, org, lifecycle_rule_created }`.

**Frontend** — the "Use Org" click handler calls `/provision`, then shows a
banner indicating whether the lifecycle rule was newly created or already in
place.

### Feature B: Telemetry log viewer

A **"Telemetry"** card in the admin panel with a **"Load Logs"** button.

**Backend** — `GET /api/orgs/{org}/telemetry` (`admin/backend/main.py`):

1. Lists objects under `telemetry/{org}/` filtered to the last 7 days.
2. Fetches up to 1 MB of JSON files, newest first.
3. Merges all `events[]` arrays, sorts by `timestamp` descending.
4. Returns `{ "events": [...], "files_fetched": n, "bytes_fetched": n }`.

**Frontend** — scrollable table: `Time/User | Level | Pivot | Message | Context`
- Level color rows: `error` → red tint, `warning` → amber tint, `info` → plain.
- `context` JSON shown as a collapsed `<details>` per row.
- Error string shown below the message when present.

---

## Phase 2: fomo web dashboard (separate repo)

**Repo**: `~/src/github.com/bprashanth/fomo/web`
**Status**: planned, not blocking Phase 1 or 1.5

A "View Logs" section in the fomo web admin that reuses existing Cognito auth
and presigned GET URL patterns already in the web dashboard.

Implementation is identical to Phase 1.5 Feature B except it uses the web
dashboard's existing auth layer (presigned GETs via Cognito) rather than the
admin panel's server-side AWS credentials.
