# Configuration and thresholds

This doc lists the main configurable values and thresholds that affect behavior in the app.

---

## Distance and GPS accuracy

These live in `lib/screens/home_screen.dart` and control how often we react to GPS updates and when we consider the user “close enough” to a site to auto-launch the pipeline.

- **`_distanceThreshold = 2.0` meters**  
  - Used as a **movement filter** for the position stream.  
  - If a new GPS fix is closer than 2 m to the last accepted one, we skip it to avoid constantly recomputing nearest site and UI state when the user is effectively standing still.

- **`_accuracyThreshold = 20.0` meters**  
  - Used as an **accuracy filter**.  
  - If `userPos.accuracy > _accuracyThreshold`, we consider the fix too inaccurate and ignore it.  
  - Roughly: “ignore positions where the reported one-sigma accuracy radius is worse than ~20 m,” which is common indoors or under poor GPS conditions.

- **`triggerRadius = 30.0` meters**  
  - Defines when the nearest site is considered “within range” so the capture pipeline can be auto-launched.  
  - Behavior:
    - If the nearest site is **within `triggerRadius`**, we treat it as *in range*:
      - The `+` button / distance panel can take you directly into the pipeline for that nearest site.
    - If all sites are **outside `triggerRadius`**, we treat the user as “not near any known site”:
      - Pressing `+` leads to the **site selection screen**, where the user can pick an existing site or create a new local site.
  - This is the main “within X meters the site is auto-chosen vs outside you must pick/add manually” configuration.

---

## Orientation and heading

### Home screen advisory

- **File:** `lib/widgets/route_advisory.dart`  
- **Inputs:** user GPS position, site GPS position, compass heading.  
- **Logic:** purely **bearing-based**:
  - Computes bearing from user → site via `Geolocator.bearingBetween`.
  - Compares that bearing to the device heading to generate messages like:
    - “You’re facing the site”
    - “Turn slightly left/right”
    - “Turn left/right”
    - “Turn around”
    - “Head N/NE/…”
  - Meaning: “which way should I turn so I’m pointing toward the site’s location?”

### Capture screen orientation dial

- **Files:** `lib/widgets/orientation_dial.dart`, `lib/screens/capture_screen.dart`  
- **Config / thresholds:**
  - Uses a fixed angular threshold of **≈15°**:
    - If the difference between `referenceHeading` and current heading is within ~15°, the dial turns green and we consider it “matched.”
  - Only active when:
    - `captureMode == 'portrait'`, and
    - `site.referenceHeading` is non-null, and
    - We have a live compass heading (`FlutterCompass`) and are not on web/PWA.
- **Meaning:** “turn around the site (left/right) to match how the reference image was taken,” not tilt.

---

## AppConfig-related toggles

These live in `lib/config/app_config.dart` and are typically set in `main.dart` during development/testing.

- **`AppConfig.isTestMode` (bool)**  
  - When `true` and `_localRoot` is set, the app reads `sites.json` from a local file path instead of S3.  
  - Also enables **mock lat/lng** (see below).

- **`AppConfig.setLocalRoot(String path)`**  
  - Sets a local `file://` root for reading `sites.json` in test mode.

- **`AppConfig.mockLat` / `AppConfig.mockLng` (double?)**  
  - When `AppConfig.isTestMode == true` and both are non-null, GPS calls in `GpsService` return a fixed position at `(mockLat, mockLng)` instead of the device’s real location.

- **`AppConfig.isGuestMode` (bool)**
  - Enabled via `AppConfig.configureGuestMode()` when the user continues as guest.
  - Behavior:
    - Sites list comes from a hardcoded JSON in `lib/data/guest_sites.dart`.
    - Uploads go to a **guest bucket** (`fomomonguest`) without Cognito auth.
    - `SiteSyncService` is skipped in guest mode.

- **`AppConfig.isTelemetryEnabled` (bool, default `true`)**
  - Controls the `TelemetryService` pipeline entirely.
  - When `false`:
    - `TelemetryService.log()` is a no-op — no events are buffered.
    - `TelemetryService.flush()` is a no-op — no S3 requests are made.
  - Set to `false` for local development, automated tests, or specific orgs
    where telemetry is not desired.
  - See `docs/observability.md` for the full telemetry design.

- **Bucket/org/region defaults**  
  - `defaultBucketName = 'fomomon'`  
  - `defaultRegion = 'ap-south-1'`  
  - `defaultOrg = 't4gc'`  
  - Resolved root for S3 paths comes from `AppConfig.getResolvedBucketRoot()`, which uses these values (or overrides set at runtime).

---

## UX tuning

- `AppConfig.nearSiteMeters` (default: 5.0)
  When the user is within this distance of a site, the route advisory shows
  "You are near the site" instead of turn-by-turn guidance to avoid noisy
  bearing flips.

- `AppConfig.coneSweepDegrees` (default: 60.0)
  The angular width of the light cone drawn on the radar panel.

---

## Where to change things

- **Distance/accuracy thresholds and trigger radius:**  
  - `lib/screens/home_screen.dart` (`_distanceThreshold`, `_accuracyThreshold`, `triggerRadius`).

- **Heading/orientation thresholds:**  
  - `lib/widgets/orientation_dial.dart` (angular match threshold ≈15°).

- **Test mode / mock location / guest mode / bucket/org/region defaults:**  
  - `lib/config/app_config.dart` (and typically toggled in `lib/main.dart` during development). 
