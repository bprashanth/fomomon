# Releases

This document describes two things:

- What we do today (current release flow).
- The intended future flow once we move to the T4GC Play Console account.

Related docs:

- `docs/app_store.md` for versioning and signing details.
- `docs/release_channels.md` for release channel background.

## Current Flow (Today)

**Summary**

- We publish only to the personal Play Console account (prashanth@).
- The only package name in use is `com.t4gc.fomomon.dev`.
- The only accepted build flavor for the store is `--flavor dev`.
- All releases should go to **Closed testing** until we qualify for Open testing.

**Why this matters**

- Google Play tracks are per package name. If we change the package name, it becomes a different app.
- Keeping everything on `com.t4gc.fomomon.dev` avoids forcing users to uninstall/reinstall.

### Release Steps (Current)

1. Bump version in `pubspec.yaml`.
   - Use `semver+versionCode` as documented in `docs/app_store.md`.
   - The `versionCode` (the `+N` part) must always increase.
2. Build the app bundle:

```bash
flutter build appbundle --flavor dev
```

3. Upload the `.aab` to the **Closed testing** track for `com.t4gc.fomomon.dev`.
4. Name the release according to the version in `pubspec.yaml`.

### Track Usage (Current)

- **Internal testing**: use only for T4GC team accounts.
- **Closed testing**: use for external testers.
- **Open testing**: only when Play Console allows us to progress.

## Future Flow (Goal)

**Summary**

- We will move publishing to the T4GC Play Console account.
- We will use the production package name `com.t4gc.fomomon`.
- This allows closed/open builds to be promoted to production without rebuilding.

### Release Steps (Future)

1. Bump version in `pubspec.yaml` and `app_config.dart` (this is just for telemetry)
2. Build the production bundle:

```bash
flutter build appbundle --flavor production
```

3. Upload to Internal/Closed/Open/Production as needed (all under `com.t4gc.fomomon`).

### Local Dev / Side-by-Side Testing (Future)

- For local installs or side-by-side testing, use flavors like `--flavor alpha` or `--flavor beta`.
- These are for developer testing only and should not be uploaded to the Play Store in the T4GC account.

```console
$ flutter run --flavor beta
```

## Testing Groups Policy

- **Internal testing**: T4GC emails only.
- **Closed and Open testing**: external tester emails only.
