# PWA Deployment - Netlify (static pre-built)

The Flutter web app is built locally and the compiled output is committed to the
repo. Netlify serves it directly with no build step.

---

## What is deployed

Only `fomomon/build/web/` is served - the compiled, minified Flutter web bundle.
The `admin/` directory and all other repo contents are never touched by Netlify.

---

## Setup 

Netlify config (`netlify.toml` at repo root)

```toml
[build]
  base    = "fomomon"
  publish = "build/web"
```

`base = "fomomon"` scopes Netlify's working directory to the Flutter app subfolder,
preventing it from seeing `requirements.txt` (the admin backend's Python deps) at the
repo root and trying to install them. `publish` is relative to `base`.

No build command - Netlify serves the pre-built output as-is.

## Deploying an update

```bash
cd fomomon/fomomon
flutter build web --release
cd ../..
git add fomomon/build/web/
git commit -m "Rebuild web"
git push origin pwa
```

Netlify picks up the push automatically and redeploys within ~30 seconds.

