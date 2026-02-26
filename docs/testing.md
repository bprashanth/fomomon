# Testing modes: Test mode, Guest mode, and Mock location

This document describes the app’s testing-related modes and how they interact: **test mode**, **guest mode**, and **mock latitude/longitude**.

---

## Guest mode

**Guest mode** is an in-field, live-test mode. It lets someone use the app without signing in, with a fixed set of sites and a separate, public S3 bucket for uploads.

### How it works

- **Entry:** User taps “Continue as Guest” on the login screen. `AppConfig.configureGuestMode()` is called (`isGuestMode = true`).
- **Sites:** The app does **not** fetch `sites.json` from the main app bucket. Instead it uses a **hardcoded** sites list from `lib/data/guest_sites.dart` (`GuestSites.guestSitesJson`). That JSON includes a `bucket_root` pointing at the guest bucket (`https://fomomonguest.s3.ap-south-1.amazonaws.com/`).
- **Bucket:** All guest uploads go to this **guest bucket**.
- **Local sites:** Guest mode also merges in any sites from local storage (`LocalSiteStorage.loadLocalSites()`), so you can use guest mode with both the hardcoded guest sites and user-created local sites.

### Intended behavior: independent of test mode

Loading of the hardcoded guest sites from `guest_sites.dart` is **only** gated by `AppConfig.isGuestMode`. It does **not** depend on `AppConfig.isTestMode`. So:

- **Guest mode with test mode off:** The app should still load the local hardcoded guest sites from `guest_sites.dart` and merge with local sites. You can use guest mode with real GPS.
- **Guest mode with test mode on:** Same guest sites, plus you can use a local file root and/or mock lat/lng if you enable them.

If guest sites do not appear when test mode is false, that is not by design; the code path does not check test mode for guest site loading. Check logs for “Guest mode: Loading guest sites” and “Error loading guest sites” to debug.

---

## Test mode

**Test mode** (`AppConfig.isTestMode = true`) is for local/offline and controlled testing:

- **Sites source:** If `setLocalRoot(...)` is set, `getResolvedBucketRoot()` returns that path (e.g. `file:///...`). The app then loads `sites.json` from the local directory instead of S3.
- **No local root:** If test mode is on but no local root is set, bucket root is still the normal HTTP bucket (same as production). So test mode alone only affects behavior when combined with **mock lat/lng** (and optionally local root).

Test mode is toggled in code (e.g. in `main.dart`); there is no UI switch.

---

## Mock latitude / longitude

**Mock lat/lng** (`AppConfig.mockLat` and `AppConfig.mockLng`) override the device’s real GPS. When set, the app uses these coordinates for:

- `GpsService.getPositionStream()`
- `GpsService.getCurrentPosition()`

**Activation:** Mock coordinates are only used when **all** of the following are true:

- `AppConfig.isTestMode == true`
- `AppConfig.mockLat != null`
- `AppConfig.mockLng != null`

So mock lat/lng is a **test-mode feature**: you enable test mode (and set mock values) to get fixed coordinates.

### Compatibility with guest mode

Mock lat/lng is **compatible with guest mode**. You can run with:

- `isGuestMode = true` (hardcoded guest sites, guest bucket, no login)
- `isTestMode = true`
- `mockLat` / `mockLng` set

That gives you an in-field-style flow (guest bucket, hardcoded sites) with fixed coordinates and no need for a real GPS or local file root.

---

## Summary

| Feature          | What it does                                                                                                                      |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **Guest mode**   | No login; hardcoded sites from `guest_sites.dart`; uploads to guest bucket; can merge with local sites. Independent of test mode. |
| **Test mode**    | Optional local file root for `sites.json`; required for mock lat/lng to take effect.                                              |
| **Mock lat/lng** | Override GPS with fixed coordinates; only active when test mode is on and both values are set. Works together with guest mode.    |

---

## Enabling in code (main.dart)

```dart
void main() async {
  // Test mode (optional local root + enables mock lat/lng)
  // AppConfig.isTestMode = true;
  // AppConfig.setLocalRoot("file:///storage/emulated/0/Download/fomomon_test/");

  // Mock GPS (requires isTestMode = true)
  // AppConfig.mockLat = 12.9746;
  // AppConfig.mockLng = 77.5937;

  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FomomonApp());
}
```

Guest mode is entered at runtime by tapping “Continue as Guest” on the login screen; it is not set in `main.dart`.
