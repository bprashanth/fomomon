# Releases

This document describes two things:

- What we do today (current release flow).
- The intended future flow once we move to the T4GC Play Console account.

Related docs:

- `docs/app_store.md` for versioning and signing details.
- `docs/release_channels.md` for release channel background.

## Current Flow (Today)

**Summary**

- We publish to the personal Play Console account (prashanth@) for Android, and
  on web via Netlify connected to the GitHub account.
- The only Android package name in use is `com.t4gc.fomomon.dev`.
- The only accepted Android build flavor for the store is `--flavor dev`.
- All Android releases should go to **Closed testing** until we qualify for Open testing.
- Web (PWA) releases are **manually triggered** by committing the built output to git.

**Why this matters**

- Google Play tracks are per package name. If we change the package name, it becomes a different app.
- Keeping everything on `com.t4gc.fomomon.dev` avoids forcing users to uninstall/reinstall.
- **Netlify has no build command**: the PWA `build/web/` directory is committed to git
  (`fomomon/.gitignore` excludes `build/` but un-ignores `build/web/` with `!/build/web/`).
  Netlify deploys whatever is in that directory at the pushed commit — no Flutter build runs
  on Netlify. **Pushing code changes without rebuilding and committing `build/web/` does NOT
  update the live PWA.** Field testing is safe across code-only pushes.

### Release Steps — Android (Current)

1. Bump version in `pubspec.yaml`.
   - Use `semver+versionCode` as documented in `docs/app_store.md`.
   - The `versionCode` (the `+N` part) must always increase.
2. Build the app bundle:

```bash
flutter build appbundle --flavor dev
```

3. Upload the `.aab` to the **Closed testing** track for `com.t4gc.fomomon.dev`.
4. Name the release according to the version in `pubspec.yaml`.

### Release Steps — Web / PWA (Current)

The PWA is hosted on Netlify. `netlify.toml` at the repo root sets the publish
directory to `fomomon/build/web` with no build command. The compiled web output
is committed to git and Netlify serves it directly.

Netlify deploy contexts (also documented in `netlify.toml`):
- **Production** (`main` branch): deployed on every push to `main`
- **Branch deploys**: disabled — only `main` gets a live deploy URL
- **Deploy Previews**: enabled — every PR against `main` gets a preview URL

**To release a new PWA version:**

1. Build:

```bash
cd fomomon
flutter build web --release
```

2. Commit and push:

```bash
git add build/web
git commit -m "Release PWA vX.Y.Z"
git push origin main
```

Netlify detects the push to `main`, deploys the new `build/web/` content, and
the live PWA updates. Users' service workers pick up the new version on the next
page load (silent, automatic — see "How the PWA updates for users" below).

**Holding the live PWA stable (e.g. during field testing):**

Simply do not rebuild and commit `build/web/`. Code-only pushes to `main` are
safe — Netlify will re-deploy the same compiled output. No Netlify dashboard
toggle is needed.

### How the PWA updates for users

There is no manual version number for the web — updates are content-based:

- Flutter web compiles to hashed JS bundles. When any source file changes, the
  bundle hashes change, and `flutter_service_worker.js` gets a new asset manifest.
- On the user's next page load, the browser detects the new service worker,
  downloads it in the background, and activates it on the following open.
- Users see no version number; the update is silent and automatic.

**`org.chromium.webapk.<hash>_v2` — what is it?**

When a user adds the PWA to their Android home screen, Chrome wraps it in a
**WebAPK** — a thin native APK registered with the OS. The package name
(`org.chromium.webapk.<hash>`) is derived from the PWA's `start_url` and
manifest; `_v2` denotes the WebAPK format generation (v2 replaced the deprecated
v1 format). Chrome manages this entirely — the developer has no control over the
package name or version.

The "version 1" visible in Android settings is Chrome's internal WebAPK
`versionCode`, starting at 1. Chrome increments it when it updates the WebAPK
shell (triggered by changes to the PWA manifest — name, icons, `start_url`,
etc.). This is **not** the Flutter app version and is not set by the developer.

### Track Usage (Current) — Android

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
