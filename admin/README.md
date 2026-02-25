# Fomomon Admin

Admin UI for managing Cognito users and S3 site configuration for the Fomomon phone app. This directory is self-contained and can be lifted into its own repo.

What this admin interface is for
1. Add, remove, and reset passwords for users linked to the phone app pool described by `auth_config.json`.
2. Manage the `sites.json` and `users.json` configs per org: review or update reference images, site names and locations, and survey questions.
3. Ensure only the phone app pool and the serverless backend have read/write access to the S3 data (see `admin/AUTH.md`).

## Prerequisites
This server uses AWS APIs via `boto3`. Credentials are resolved using the standard AWS default chain:
- AWS CLI configuration (`~/.aws/credentials`, `~/.aws/config`) after `aws configure` or `aws sso login`.
- Environment credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`).
- Instance or task roles (EC2/ECS) if running in AWS.

If credentials or bucket access are missing, the UI will show an error banner.     
A backend health check is available at `/api/health`.

## Environment
Create `admin/.env` from the template and set values.

```
cp admin/.env.example admin/.env
```

- `AWS_REGION` (required): AWS region for Cognito, S3, and IAM.
- `FOMOMON_BUCKET` (required): S3 bucket name containing org data, sites config, and `auth_config.json`.
- `AUTH_CONFIG_KEY` (optional, default `auth_config.json`): Key path inside the bucket for the auth config.

See [AUTH.md](AUTH.md) for specifics around how these are handled. 

## Start the server
From the `admin/` directory (treat this as its own repo root):

```
cd admin
source .venv/bin/activate
uv pip install -r backend/requirements.txt
uvicorn backend.main:app --reload --port 8090
```

Then open `http://localhost:8090`.


