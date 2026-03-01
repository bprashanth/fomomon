# PWA Testing Guide

## Prerequisites — S3 CORS

Before testing any upload or ghost image flow from the browser, the S3 bucket
must have a CORS rule that allows browser clients to make presigned requests.

**This is a one-time setup managed via the admin interface:**

1. Run the admin backend (`cd admin && uvicorn backend.main:app --reload`).
2. Open the admin UI in a browser.
3. Click **"Sync auth_config.json"**.
4. The button now enforces bucket policy, IAM role policy, **and CORS** in one
   step. The success message will show `CORS: changed` on first run and
   `CORS: no change` on subsequent runs.

The CORS rule applied allows all origins (`*`) with `GET`, `PUT`, `HEAD`
methods so the bucket works with any PWA deployment and any localhost dev port.
See `admin/API.md → POST /api/auth_config/sync` for the full rule detail.

Without this step:
- Ghost image overlays will fail to load (browser blocks the presigned GET)
- Session uploads will fail with "no network connection" (browser blocks the
  presigned PUT)

---

## TL;DR — which option to use


| Goal                                     | Use                                                           |
| ---------------------------------------- | ------------------------------------------------------------- |
| Quick laptop browser test                | Option A (LAN IP with `flutter run`)                          |
| Phone GPS + camera + permissions working | Option B (USB port forwarding)                                |
| Phone standalone install ("Install app") | Option B (USB) or Option C (python build server on localhost) |
| Full offline / service-worker test       | Option C (production build)                                   |


---

## Why HTTPS / localhost matters

The browser enforces a **secure context** for:


| API                                           | Requires                                         |
| --------------------------------------------- | ------------------------------------------------ |
| Geolocation (`navigator.geolocation`)         | HTTPS or `localhost`                             |
| DeviceMotion / accelerometer (`sensors_plus`) | HTTPS or `localhost`                             |
| Camera / getUserMedia                         | HTTPS or `localhost`                             |
| Service Worker registration                   | HTTPS or `localhost`                             |
| PWA "Install app" prompt                      | HTTPS or `localhost` + service worker registered |


**A plain `http://192.168.x.x:PORT` URL fails all of the above.** The browser silently
refuses — no permission prompt appears, no error is shown to the user. The app gets stuck
at "Acquiring GPS..." because `GpsService.ensurePermission()` returns `false` immediately
without ever showing the location dialog.

Camera and accelerometer have the same restriction, so the full capture flow also fails on
a plain LAN IP on Android Chrome.

---

## Option A — LAN IP (`flutter run`, laptop only)

Good for: **rapid iteration on a laptop browser**. Camera, GPS, and sensors work because
the laptop's Chrome treats `localhost` / `0.0.0.0` as secure. The phone cannot access
this URL in a way that grants permissions.

```bash
cd fomomon/fomomon
flutter run -d chrome --web-port=5175 --web-hostname=192.168.29.234
# Chrome opens on laptop to http://192.168.29.234:5175
# Phone can load the page but GPS / camera WILL NOT WORK on the phone via this URL
```

Alternatively, omit `--web-hostname` to bind to localhost only:

```bash
flutter run -d chrome --web-port=5175
# Access http://localhost:5175 on the laptop — all APIs work there
```

---

## Option B — USB Port Forwarding (recommended for phone testing)

Phone accesses the dev server via `localhost`, which Chrome treats as secure.
GPS, camera, accelerometer, and service worker all work.

### Steps

1. Connect phone to laptop via USB cable.
2. On the phone: enable **Developer Options** → enable **USB Debugging** → accept the
  connection prompt that appears on the phone.
3. Verify the phone is seen:
  ```bash
   adb devices
   # Should list your phone, e.g.:
   # R5CT306XXXX    device
  ```
   If it shows `unauthorized`, unlock the phone and tap "Allow" on the USB debugging dialog.
   Also ensure the USB connection mode is set to **File Transfer** (not Charging only).
4. Start the Flutter dev server on the laptop:
  ```bash
   cd fomomon/fomomon
   flutter run -d chrome --web-port=5175 --web-hostname=0.0.0.0
   # Server listens on all interfaces on port 5175
  ```
   Note: `--web-hostname=0.0.0.0` makes Chrome on the laptop open to `http://0.0.0.0:5175`
   which works there (Chrome on Linux treats 0.0.0.0 like localhost). Alternatively use
   `--web-hostname=localhost` and forward from localhost:
5. Open Chrome on the **laptop**, go to `chrome://inspect/#devices`.
  Under **Port forwarding**, click **Add rule**:
   Click **Enable port forwarding**.
6. On the phone, open Chrome and navigate to:
  ```
   http://localhost:5175
  ```
   The phone's Chrome tunnels through USB to the laptop's port 5175. The URL is
   `localhost` from the browser's perspective → all secure-context APIs work.
7. First visit: Chrome on the phone will ask for Location and Camera permissions.
  Tap **Allow** for both.

### Troubleshooting port forwarding

- If `adb devices` shows nothing: install `adb` (`sudo apt install adb`) and replug USB.
- If port forwarding isn't working: try `adb reverse tcp:5175 tcp:5175` in terminal
(does the same as the Chrome DevTools UI).
- If permissions were previously denied: go to Chrome Settings → Site Settings →
`localhost` → reset Location and Camera to "Ask".

---

## Option C — Production build served locally

No hot-reload. Rebuild after each change. Useful for testing the service worker and
PWA installation flow.

```bash
cd fomomon/fomomon

# Build
flutter build web

# Serve (binds to all interfaces)
cd build/web
python3 -m http.server 5175 --bind 0.0.0.0
```

- **Laptop**: `http://localhost:5175` — all APIs work, service worker registers
- **Phone via USB port forwarding**: `http://localhost:5175` — same as above
- **Phone via LAN IP**: `http://192.168.29.234:5175` — GPS / camera / SW still blocked

The production build includes `flutter_service_worker.js` (Workbox-based), which
registers automatically. This is required for the PWA install prompt.

---

## Installing as a standalone PWA (no browser bar)

Requirements (all three must be met):


| Requirement                                                  | How fomomon satisfies it                           |
| ------------------------------------------------------------ | -------------------------------------------------- |
| HTTPS or localhost                                           | USB port forwarding → `localhost`                  |
| `manifest.json` with `display: standalone` and 192/512 icons | `web/manifest.json` ✅ already present              |
| Service worker with a fetch handler                          | `flutter_service_worker.js` in production builds ✅ |


### Install steps (Android Chrome)

1. Build and serve (`flutter build web` + python server, or use USB port forwarding
  with `flutter run`).
2. Open `http://localhost:5175` on the phone.
3. In Chrome's menu (three dots), look for **"Install app"**.
  - If you only see **"Add to Home Screen"** (not "Install app"), the service worker
   has not registered yet. This happens in debug `flutter run` mode. Use the
   production build instead.
  - Wait a few seconds after the page loads for the service worker to install, then
  check the menu again.
4. Tap **Install**. The app icon appears on the home screen.
5. Launch from the home screen — no address bar, no tabs.

### Clearing a stale install

If you previously added the site as a bookmark (before the service worker was active):

1. Long-press the home screen icon → **Remove**.
2. In Chrome: Settings → Site Settings → `localhost` → **Clear & reset**.
3. Revisit and install fresh.

---

## Permissions reference


| Permission     | When asked                                         | If denied                                                                     |
| -------------- | -------------------------------------------------- | ----------------------------------------------------------------------------- |
| Location       | First time `GpsService.ensurePermission()` runs    | "Acquiring GPS..." forever; user must go to Chrome Site Settings to re-enable |
| Camera         | First time `CameraController.initialize()` runs    | Camera view stays black; user must re-enable in Site Settings                 |
| Motion sensors | First `accelerometerEvents` subscription (Android) | Inclinometer shows 0°; no visible error (gracefully degraded)                 |


To reset permissions on Android Chrome: **Settings → Site Settings → All Sites →
`localhost` → Reset permissions**.

---

## Checklist for a passing smoke test (Option B — USB)

- `adb devices` shows phone as `device` (not `unauthorized`)
- Port forwarding enabled in `chrome://inspect/#devices` for port 5175
- App loads at `http://localhost:5175` on phone — no blank screen
- Location permission dialog appears on first load → tap Allow
- Camera permission dialog appears when entering capture screen → tap Allow
- "Acquiring GPS..." resolves within ~10s and the radar map appears
- Site markers appear on the radar (requires network to fetch sites.json)
- Portrait capture → image appears in confirm screen
- Landscape capture → proceed to survey or home
- Session appears in upload gallery
- Upload succeeds → files visible in S3

---

## Running on laptop vs phone — quick reference

```bash
# Laptop dev (hot reload, localhost, all APIs work)
flutter run -d chrome --web-port=5175

# Phone dev (hot reload via USB, all APIs work on phone too)
#   1. adb devices  ← confirm phone connected
#   2. chrome://inspect → port forwarding: 5175 → localhost:5175
flutter run -d chrome --web-port=5175 --web-hostname=0.0.0.0
#   Phone: open http://localhost:5175

# Phone production build (no hot reload; service worker + install prompt)
flutter build web && python3 -m http.server 5175 --bind 0.0.0.0 --directory build/web
#   Laptop: http://localhost:5175
#   Phone via USB forward: http://localhost:5175
```

