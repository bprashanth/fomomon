# fomomon

A Flutter app for field monitoring of sites. Teams navigate to a site, capture portrait and landscape images against a reference ("ghost") image, complete a short survey, and batch-upload when connectivity is available.

```console
flutter run --flavor {alpha,dev}
```

---

## What it does

The core workflow is:

1. **Find a site** - GPS tracking shows nearby sites and how far away they are. A compass/bearing widget guides orientation toward the target.
2. **Launch the pipeline** - Within ~30 m of a site, tap `+` to begin. Out of range, pick a site manually or create a new local one.
3. **Capture images** - Portrait and landscape images, each compared to a cached reference ("ghost") image with an opacity slider. An orientation dial guides heading match.
4. **Complete a survey** - Answer site-specific questions (text or MCQ).
5. **Upload** - Sessions are saved locally first. When online, open the upload queue and push everything to S3.

---

## Related infrastructure

This app is one part of a broader system:

| Component | Repo | Local path |
|---|---|---|
| Flutter app (this) | `bprashanth/fomomon` | `~/src/github.com/bprashanth/fomomon/fomomon` |
| Serverless Lambda API | `bprashanth/good-shepherd` | `~/src/github.com/bprashanth/good-shepherd/server` |
| Web dashboard | `bprashanth/fomo` | `~/src/github.com/bprashanth/fomo/web` |

All three share the same AWS Cognito auth (user pool, identity pool) and the same S3 bucket structure. If working from a fork, replace `bprashanth` with your GitHub username in the paths above.

---

## Configuration

App configuration is documented in [docs/config.md](../docs/config.md). The main knobs are:

- **GPS/distance thresholds** - movement filter, accuracy filter, trigger radius (`lib/screens/home_screen.dart`)
- **Heading match threshold** - angular tolerance for the orientation dial (`lib/widgets/orientation_dial.dart`)
- **Test/guest/mock mode** - local file roots, mock GPS coordinates, guest bucket (`lib/config/app_config.dart`)

Configuration across the full system (env vars, Netlify, Lambda) is somewhat disjoint; the above covers only the Flutter app.

---

## App structure

### Screens

These are the main screens, documentation might drift from reality over time

| Screen | Purpose |
|---|---|
| `login_screen.dart` | Email/password login with org selection; "Continue as Guest" option |
| `site_prefetch_screen.dart` | Loading screen while sites.json and reference images are fetched/cached |
| `home_screen.dart` | Main screen: GPS tracking, site markers, distance panel, compass heading, `+` button |
| `site_selection_screen.dart` | Pick an existing site or create a new local site when out of trigger range |
| `capture_screen.dart` | Camera with ghost image overlay, orientation dial, focus control |
| `confirm_screen.dart` | Review captured image; retake or proceed |
| `survey_screen.dart` | Answer site survey questions; saves session to disk on submit |
| `upload_queue_screen.dart` | List of pending sessions with upload dial and session detail view |

### Widgets

These are the main widgets, documentation might drift from reality over time

| Widget | Purpose |
|---|---|
| `gps_feedback_panel.dart` | Radar visualization of user and nearby sites; uses accelerometer tilt |
| `distance_info_panel.dart` | Shows nearest site distance and launch button |
| `route_advisory.dart` | Directional text banner ("Turn Right", "You're facing the site", etc.) |
| `orientation_dial.dart` | Circular indicator showing current vs. reference heading; turns green on match |
| `plus_button.dart` | Main capture trigger; highlights when within trigger radius |
| `upload_dial_widget.dart` | Animated dial for batch upload; handles auth errors with login redirect |
| `online_mode_button.dart` | Navigates to upload queue |
| `gps_feedback_panel.dart` | Radar of nearby sites with pulsing user position dot |
| `session_detail_dialog.dart` | Modal showing full captured session details |
| `privacy_policy_dialog.dart` | Privacy notice shown at login |

### Services

These are the main services, documentation might drift from reality over time

| Service | Purpose |
|---|---|
| `auth_service.dart` | AWS Cognito login, token refresh, temporary upload credentials |
| `site_service.dart` | Fetches and caches sites.json from S3; prefetches reference images |
| `upload_service.dart` | Uploads sessions (images + JSON) to S3 via presigned URLs |
| `site_sync_service.dart` | Syncs locally-created sites and reference headings back to remote sites.json |
| `gps_service.dart` | Location stream, distance calculations, permission handling |
| `heading_service.dart` | One-shot compass heading reads |
| `s3_signer_service.dart` | AWS Signature V4 presigned GET/PUT URLs |
| `fetch_service.dart` | HTTP GET wrapper (authenticated and unauthenticated) |
| `local_session_storage.dart` | CRUD for captured sessions on device (`/documents/sessions/`) |
| `local_site_storage.dart` | CRUD for user-created local sites (`/documents/local_sites.json`) |
| `local_image_storage.dart` | Saves captured images to permanent location (`/documents/images/`) |

### Models

`Site`, `CapturedSession`, `SurveyQuestion`, `SurveyResponse`, `AuthConfig`, `ConfirmScreenArgs`, `LoginError`

---

## Navigation flow

```
main()
  |-- [stored session] -> HomeScreen
  |- [no session]    -> LoginScreen -> SitePrefetchScreen -> HomeScreen

HomeScreen
  |-- [within ~30meters]  -> CaptureScreen (portrait)
  |                       -> ConfirmScreen
  |                       -> CaptureScreen (landscape)
  |                    -> ConfirmScreen
  |                    -> SurveyScreen -> (save session) -> HomeScreen
  |-- [out of range] -> SiteSelectionScreen -> CaptureScreen ...
  |- [upload queue] -> UploadQueueScreen -> UploadService -> SiteSyncService
```

---

## Key design notes

- **Offline-first** - Sessions are saved to disk immediately. Upload is a separate explicit step.
- **Lazy auth** - Full session restoration (network call) is deferred until upload time. The app starts from a stored refresh token without a network round-trip.
- **Presigned URLs** - All S3 access uses short-lived presigned GET/PUT URLs; no bearer tokens in requests.
- **Guest mode** - A no-auth path using a public bucket (`fomomonguest`) with hardcoded sites. Useful for demos and testing without Cognito.
- **Local sites** - Users can create sites out-of-range. These are synced to remote sites.json after the first successful upload.
- **Reference images ("ghosts")** - Cached locally at app start. Used as overlays in the capture screen to guide framing.
