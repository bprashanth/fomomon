# Admin Backend API

FastAPI backend in `backend/main.py`. No authentication — access is controlled
by the AWS credentials of whoever runs the server. All endpoints consume and
return JSON unless noted.

Base URL (local): `http://localhost:8000`

---

## Recommended invocation order

A frontend should call these in roughly this sequence on startup:

1. `GET /api/health` — abort if not ok
2. `GET /api/config` — get bucket name and region for display
3. `GET /api/orgs` — populate the org selector
4. `GET /api/password_policy` — show password rules before the Add User form

After the user selects or enters an org:

5. `POST /api/orgs/{org}/provision` — ensure S3 prefixes and lifecycle rule exist
6. `GET /api/orgs/{org}/users` — load org user list
7. `GET /api/users` — load global Cognito user list (for cross-referencing)

On demand:

- `POST /api/orgs/{org}/users` — add / update a user
- `DELETE /api/orgs/{org}/users/{username}` — remove a user
- `PUT /api/orgs/{org}/users/{username}/password` — reset password
- `GET /api/orgs/{org}/sites` / `PUT` / `POST .../upload` — manage sites.json
- `POST /api/orgs/{org}/ghosts` — upload a reference image
- `GET /api/orgs/{org}/telemetry` — fetch telemetry logs
- `POST /api/auth_config/sync` — enforce IAM/bucket permissions

---

## Endpoints

### GET /api/health

Checks that env vars are set and AWS credentials can reach the bucket.

**Response (ok)**
```json
{ "ok": true }
```

**Response (failure)**
```json
{ "ok": false, "message": "AWS credentials not available. ..." }
```

Possible failure messages:
- Missing env vars (`AWS_REGION`, `FOMOMON_BUCKET`)
- AWS credentials not valid (STS call failed)
- Bucket inaccessible (credentials lack `s3:HeadBucket`)

---

### GET /api/config

Returns server configuration values for display.

**Response**
```json
{
  "bucketName": "fomomon",
  "bucketRootTemplate": "https://fomomon.s3.amazonaws.com/{org}/",
  "region": "ap-south-1"
}
```

---

### GET /api/orgs

Lists all top-level S3 prefixes in the bucket that represent orgs.

The `telemetry/` prefix is excluded — it is not an org, it is where telemetry
data for all orgs lives.

**Response**
```json
{ "orgs": ["ncf", "t4gc", "testorg"] }
```

---

### POST /api/orgs/{org}/provision

Idempotent. Ensures the following S3 structure exists for an org and that the
telemetry lifecycle rule is in place. Safe to call every time an org is selected.

**What it does:**
1. Creates `{org}/` placeholder key in S3 if missing.
2. Creates `telemetry/{org}/` placeholder key in S3 if missing.
3. Ensures the single `telemetry/` lifecycle rule exists on the bucket
   (90-day expiry). See [Lifecycle rule safety](#lifecycle-rule-safety) below.

**Request:** no body required.

**Response**
```json
{
  "ok": true,
  "org": "t4gc",
  "lifecycle_rule_created": false
}
```

`lifecycle_rule_created` is `true` the first time the rule is written, `false`
on every subsequent call.

---

### GET /api/orgs/{org}/users

Returns users for the org, cross-referenced against Cognito.

**Response**
```json
{
  "org": "t4gc",
  "users": [
    {
      "profile": {
        "name": "Srini",
        "email": "srini@ncf-india.org",
        "username": "srini",
        "password": "..."
      },
      "cognito": {
        "username": "srini",
        "email": "srini@ncf-india.org",
        "status": "CONFIRMED",
        "enabled": true
      }
    }
  ]
}
```

`cognito` is `null` if the user is in `users.json` but not in Cognito.

---

### POST /api/orgs/{org}/users

Creates or updates a user. If the username (derived from `name`) already exists
in Cognito, the password is updated instead.

Also calls `s3.ensure_org_prefix(org)` — safe to call even before `provision`.

**Request body**
```json
{
  "org": "t4gc",
  "name": "Srini",
  "email": "srini@ncf-india.org",
  "password": "SecurePass1!"
}
```

`org` in the body must match the `{org}` path parameter.

The `name` field is lowercased and used as the Cognito username. It is also the
login name in the app.

**Response**
```json
{ "ok": true, "created": true }
```

`created` is `false` if the user already existed (password was updated).

**Errors**
- `400` — org mismatch, invalid password (Cognito policy violation), or other
  Cognito error. `detail` contains the human-readable message.

---

### DELETE /api/orgs/{org}/users/{username}

Removes the user from Cognito and from `{org}/users.json`.

**Response**
```json
{ "ok": true }
```

---

### PUT /api/orgs/{org}/users/{username}/password

Updates the user's password in Cognito and in `{org}/users.json`.

**Request body**
```json
{ "password": "NewPass1!" }
```

**Response**
```json
{ "ok": true }
```

---

### GET /api/users

Lists all users in the Cognito user pool (all orgs combined).

**Response**
```json
{
  "users": [
    {
      "username": "srini",
      "name": "Srini",
      "email": "srini@ncf-india.org",
      "status": "CONFIRMED",
      "enabled": true
    }
  ]
}
```

---

### GET /api/auth_config

Returns the contents of `auth_config.json` from S3.

**Response** — passthrough of the JSON stored in the bucket:
```json
{
  "userPoolId": "ap-south-1_xxx",
  "clientId": "...",
  "identityPoolId": "ap-south-1:...",
  "region": "ap-south-1"
}
```

`404` if the file does not exist.

---

### GET /api/password_policy

Returns the Cognito user pool password policy.

**Response**
```json
{
  "minimumLength": 8,
  "requireUppercase": true,
  "requireLowercase": true,
  "requireNumbers": true,
  "requireSymbols": false
}
```

---

### POST /api/auth_config/sync

Enforces correct IAM and S3 bucket permissions:

1. Ensures the bucket policy allows only `auth_config.json` to be publicly
   readable, and removes any overly-broad public-read statements.
2. Ensures the Cognito identity pool's authenticated role has
   `s3:ListBucket` + `s3:GetObject` + `s3:PutObject` on the bucket.

**Response**
```json
{
  "ok": true,
  "bucketPolicyChanged": true,
  "rolePolicyChanged": false,
  "roleName": "Cognito_fomomonAuth_Role",
  "publicAccessDetected": false
}
```

On misconfiguration (missing `auth_config.json`, missing env vars) returns a
`400` with setup instructions including CLI commands.

---

### GET /api/orgs/{org}/sites

Returns `{org}/sites.json` from S3.

**Response**
```json
{
  "org": "t4gc",
  "sites_json": {
    "bucket_root": "https://fomomon.s3.amazonaws.com/t4gc",
    "sites": [ ... ]
  }
}
```

`sites_json` is `null` if the file does not exist yet.

---

### PUT /api/orgs/{org}/sites

Writes a new `{org}/sites.json` to S3.

**Request body**
```json
{ "sites_json": { "bucket_root": "...", "sites": [ ... ] } }
```

**Response**
```json
{ "ok": true }
```

---

### POST /api/orgs/{org}/sites/upload

Uploads a `sites.json` file as multipart form data.

**Request:** `multipart/form-data` with field `file` (must be `.json`).

**Response**
```json
{ "ok": true }
```

---

### POST /api/orgs/{org}/ghosts

Uploads a reference (ghost) image for a site. Stores it at
`{org}/{site_id}/{timestamp}-{name}-{n}{ext}`.

**Request:** `multipart/form-data`
- `site_id` (string) — site identifier
- `orientation` (string) — `portrait` or `landscape`
- `image` (file) — the image file

**Response**
```json
{
  "ok": true,
  "key": "t4gc/site_001/20240115T103000-building-1.jpg",
  "relative_path": "site_001/20240115T103000-building-1.jpg"
}
```

`relative_path` is relative to the org bucket root and should be stored in
`sites.json` as `reference_portrait` or `reference_landscape`.

---

### GET /api/orgs/{org}/telemetry

Fetches and merges telemetry events for the last 7 days (or `?days=N`).

**Query params**
- `days` (int, default `7`) — how many days back to look

**What it does:**
1. Lists objects under `telemetry/{org}/` with `LastModified >= now - days`.
2. Fetches up to 1 MB of files, newest first.
3. Merges all `events[]` arrays from each file.
4. Sorts events by `timestamp` descending.
5. Attaches `_userId` and `_appVersion` from the file envelope to each event.

**Response**
```json
{
  "events": [
    {
      "timestamp": "2024-01-15T10:28:00Z",
      "level": "error",
      "pivot": "session_upload_failed",
      "message": "Session upload failed for site_001",
      "error": "AuthSessionExpiredException: token expired",
      "context": { "siteId": "site_001", "sessionId": "..." },
      "_userId": "srini",
      "_appVersion": "1.1.0+9"
    }
  ],
  "files_fetched": 3,
  "bytes_fetched": 4120
}
```

`level` values: `info`, `warning`, `error`.

---

### GET /api/s3

Generates a presigned GET URL for an S3 object and redirects to it (1-hour
expiry). Used by the frontend to display reference images inline.

**Query params**
- `key` (string) — S3 object key, e.g. `t4gc/site_001/image.jpg`

**Response:** `302 Redirect` to the presigned S3 URL.

---

## Lifecycle rule safety

`POST /api/orgs/{org}/provision` calls `ensure_telemetry_lifecycle_rule()`,
which runs a GET-merge-PUT cycle on the **bucket lifecycle configuration**.

It is important to understand what this does and does not touch:

### What it operates on

S3 lifecycle configuration is a **metadata object attached to the bucket** — a
JSON list of rules that tells AWS when to automatically expire or transition
objects. It is completely separate from the bucket's actual data. This API call
reads and writes **only that metadata list**.

```
Bucket lifecycle config  ←  what GET/PUT here operates on
   Rule A: { Prefix: "telemetry/", Expiry: 90d }  ← the rule we add
   Rule B: ...any other existing rules (preserved)

Bucket data (completely untouched by this call)
   fomomon/
     auth_config.json
     t4gc/                ← org data, never touched by this call
       sites.json
       users.json
       site_001/image.jpg
     telemetry/           ← only objects here will eventually expire
       t4gc/2024-01-15/srini_123.json
```

### The GET-merge-PUT sequence

```python
# 1. GET current rules (may be empty if no rules exist yet)
resp = s3.get_bucket_lifecycle_configuration(Bucket=bucket)
rules = resp.get("Rules", [])

# 2. Check if a matching rule already exists — skip if so
for rule in rules:
    if rule["Filter"]["Prefix"] == "telemetry/" and rule["Status"] == "Enabled":
        return False  # already in place, do nothing

# 3. Append our rule to the existing list (never replace or remove other rules)
rules.append({ "ID": "expire-telemetry-90d", "Filter": {"Prefix": "telemetry/"}, ... })

# 4. PUT the merged list back
s3.put_bucket_lifecycle_configuration(Bucket=bucket, LifecycleConfiguration={"Rules": rules})
```

The `put_bucket_lifecycle_configuration` API replaces the entire rule list, so
we must GET first and merge. Our code only appends — it never removes or
modifies existing rules.

### Scope of the rule itself

The rule we add has `"Filter": {"Prefix": "telemetry/"}`. S3 prefix filters are
exact string matches — they apply only to objects whose key starts with
`telemetry/`. No object under `t4gc/`, `ncf/`, or any other org prefix will
ever be expired by this rule.

This is the core reason why telemetry files live under `telemetry/{org}/`
rather than `{org}/telemetry/`: the expiry prefix stays completely outside
the org namespace, making accidental data loss structurally impossible.
