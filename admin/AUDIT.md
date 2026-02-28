# Auditing the admin interface

The admin panel enforces two categories of rules against the S3 bucket and
Cognito: **access policy** (who can read/write what) and **data lifecycle**
(how long telemetry is retained). Both are idempotent — re-running them
converges to the desired state without causing harm.

---

## Rule 1 — Bucket access policy

**Enforced by:** `POST /api/auth_config/sync`
**UI trigger:** "Sync auth_config.json" button
**Scope:** S3 bucket policy + Cognito identity pool role policy

### What it enforces

| Subject | Rule |
|---|---|
| Bucket policy | Public `s3:GetObject` allowed **only** on `auth_config.json`. All other overly-broad public-read statements are removed. |
| Cognito identity role | `s3:ListBucket` on the bucket ARN; `s3:GetObject` + `s3:PutObject` on `bucket/*`. |

### Audit command

```console
# Check bucket policy — only auth_config.json should be publicly readable
aws s3api get-bucket-policy \
  --bucket fomomon \
  --region ap-south-1 \
  --output json \
| jq '.Policy | fromjson | .Statement[] | {sid: .Sid, effect: .Effect, principal: .Principal, action: .Action, resource: .Resource}'
```

Expected: one `Allow` statement with `Principal: "*"` scoped to
`arn:aws:s3:::fomomon/auth_config.json` only. No `"*"` principal with
`s3:PutObject` or `s3:GetObject` on `arn:aws:s3:::fomomon/*`.

```console
# Check Cognito identity role policy
aws iam get-role-policy \
  --role-name <Cognito_fomomonAuth_Role> \
  --policy-name <role-name>-bucket-access \
| jq '.PolicyDocument.Statement[] | {effect: .Effect, actions: .Action, resources: .Resource}'
```

Expected: `s3:ListBucket` on the bucket ARN and `s3:GetObject` + `s3:PutObject`
on `arn:aws:s3:::fomomon/*`.

---

## Rule 2 — Telemetry lifecycle

**Enforced by:** `POST /api/orgs/{org}/provision?bucket=<bucket>`
**UI trigger:** "Use Org" button (called on every org selection)
**Scope:** S3 bucket lifecycle configuration, prefix `telemetry/` only

### What it enforces

Telemetry files written by the Flutter app under `telemetry/{org}/` are
automatically expired after 90 days. The rule is scoped to the `telemetry/`
prefix only — no org data (`{org}/sites.json`, `{org}/users.json`, images) is
ever touched. See `docs/observability.md` for the rationale behind the
`telemetry/{org}/` path structure.

| Field | Value |
|---|---|
| Prefix | `telemetry/` |
| Expiry | 90 days |
| Status | Enabled |

### Audit command

```console
aws s3api get-bucket-lifecycle-configuration \
  --bucket fomomon \
  --region ap-south-1 \
  --output json \
| jq '.Rules[] | {
    id:          .ID,
    prefix:      (.Filter.Prefix // .Filter.And.Prefix // .Prefix // "(empty=ALL)"),
    status:      .Status,
    expiry_days: .Expiration.Days
  }'
```

Expected output:

```json
{
  "id": "expire-telemetry-90d",
  "prefix": "telemetry/",
  "status": "Enabled",
  "expiry_days": 90
}
```

**Red flags:**
- `"prefix": ""` — rule covers the entire bucket; would delete all org data.
- `"prefix": "t4gc/"` or any org name — rule covers org data directly.

### Remove the rule (if needed)

```console
aws s3api delete-bucket-lifecycle \
  --bucket fomomon \
  --region ap-south-1
```

This removes all lifecycle rules. Re-run provision via the admin UI to
re-apply the correct rule.

---

## Rule 3 — Org S3 structure

**Enforced by:** `POST /api/orgs/{org}/provision?bucket=<bucket>`
**UI trigger:** "Use Org" button
**Scope:** S3 object prefixes

### What it enforces

Ensures the following placeholder keys exist so the org is visible in S3
prefix listings and the telemetry viewer has a valid path to enumerate:

| Key | Purpose |
|---|---|
| `{org}/` | Org data root — sites.json, users.json, images live here |
| `telemetry/{org}/` | Telemetry root — flushed by the Flutter app, expired by Rule 2 |

### Audit command

```console
# List top-level prefixes — org names and telemetry/ should appear
aws s3api list-objects-v2 \
  --bucket fomomon \
  --region ap-south-1 \
  --delimiter "/" \
| jq '[.CommonPrefixes[].Prefix]'

# Verify telemetry prefix exists for a specific org
aws s3api list-objects-v2 \
  --bucket fomomon \
  --region ap-south-1 \
  --prefix "telemetry/t4gc/" \
  --delimiter "/" \
| jq '[.CommonPrefixes[].Prefix // .Contents[].Key]'
```
