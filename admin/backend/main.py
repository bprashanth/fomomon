import json
import os
from typing import List, Optional, Dict, Any
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
import re
from dotenv import load_dotenv
import boto3
from botocore.exceptions import ClientError

from .cognito_service import CognitoService
from .s3_service import S3Service


ADMIN_ROOT = Path(__file__).resolve().parents[1]
FRONTEND_DIR = ADMIN_ROOT / "frontend"
ENV_PATH = ADMIN_ROOT / ".env"
load_dotenv(ENV_PATH)

AWS_REGION = os.getenv("AWS_REGION")
BUCKET_NAME = os.getenv("FOMOMON_BUCKET")
AUTH_CONFIG_KEY = os.getenv("AUTH_CONFIG_KEY") or "auth_config.json"

app = FastAPI(title="Fomomon Admin", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"] ,
    allow_headers=["*"],
)

cognito = CognitoService(
    app_name="",
    app_type="",
    region=AWS_REGION or "",
    bucket_name=BUCKET_NAME or "",
)

s3 = S3Service(bucket_name=BUCKET_NAME or "", region=AWS_REGION or "")


def _bucket_root_template() -> str:
    if not BUCKET_NAME:
        return "https://<bucket>.s3.amazonaws.com/{org}/"
    return f"https://{BUCKET_NAME}.s3.amazonaws.com/{{org}}/"


class UserInput(BaseModel):
    org: str = Field(..., min_length=1)
    name: str
    email: str
    password: str


class PasswordInput(BaseModel):
    password: str


class PasswordPolicyOutput(BaseModel):
    minimumLength: int = 0
    requireUppercase: bool = False
    requireLowercase: bool = False
    requireNumbers: bool = False
    requireSymbols: bool = False


class SitesPayload(BaseModel):
    sites_json: Dict[str, Any]


class UsersJson(BaseModel):
    bucket_root: str
    org: str
    users: List[Dict[str, Any]]
    updated_at: str


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def _normalize_username(name: str) -> str:
    return name.strip().lower()

def _sanitize_filename(name: str) -> str:
    name = re.sub(r"\\s+", "-", name.strip().lower())
    name = re.sub(r"[^a-z0-9._-]+", "-", name)
    name = re.sub(r"-{2,}", "-", name).strip("-")
    return name or "image"

def _missing_env_vars() -> List[str]:
    required = ["AWS_REGION", "FOMOMON_BUCKET"]
    return [name for name in required if not os.getenv(name)]


def _aws_credentials_ok(region: str) -> Optional[str]:
    try:
        boto3.client("sts", region_name=region).get_caller_identity()
    except Exception:
        return (
            "AWS credentials not available. Log in with the AWS CLI "
            "(aws configure or aws sso login), or provide environment credentials."
        )
    return None


def _bucket_access_ok(bucket_name: str, region: str) -> Optional[str]:
    try:
        boto3.client("s3", region_name=region).head_bucket(Bucket=bucket_name)
    except Exception:
        return (
            f"AWS credentials do not have access to bucket {bucket_name}. "
            "Ensure the admin principal has read/write access."
        )
    return None


def _get_auth_config_from_bucket() -> Optional[Dict[str, Any]]:
    try:
        resp = s3.s3.get_object(Bucket=BUCKET_NAME, Key=AUTH_CONFIG_KEY)
        body = resp["Body"].read().decode("utf-8")
        return json.loads(body)
    except s3.s3.exceptions.NoSuchKey:
        return None
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") in ("NoSuchKey", "404"):
            return None
        raise


def _setup_instructions() -> Dict[str, Any]:
    bucket = BUCKET_NAME or "<bucket>"
    region = AWS_REGION or "<region>"
    key = AUTH_CONFIG_KEY
    create_bucket_cmd = (
        f"aws s3api create-bucket --bucket {bucket} --region {region} "
        f"--create-bucket-configuration LocationConstraint={region}"
    )
    upload_cmd = (
        f"aws s3api put-object --bucket {bucket} --key {key} "
        f"--body auth_config.json --content-type application/json"
    )
    return {
        "message": "auth_config.json is missing or the bucket is not accessible.",
        "steps": [
            "Ensure the S3 bucket exists and your AWS credentials can access it.",
            "Create auth_config.json with the correct Cognito IDs.",
            "Upload auth_config.json to the bucket.",
        ],
        "example_auth_config": {
            "userPoolId": "<user_pool_id>",
            "clientId": "<app_client_id>",
            "identityPoolId": "<identity_pool_id>",
            "region": region,
        },
        "commands": [
            create_bucket_cmd,
            upload_cmd,
        ],
    }


def _require_auth_config() -> Dict[str, Any]:
    config = _get_auth_config_from_bucket()
    if not config:
        raise HTTPException(status_code=400, detail="auth_config.json not found.")
    required = ["userPoolId", "clientId", "identityPoolId", "region"]
    missing = [key for key in required if not config.get(key)]
    if missing:
        raise HTTPException(
            status_code=400,
            detail=f"auth_config.json is missing required fields: {', '.join(missing)}.",
        )
    return config


def _user_pool_id() -> str:
    config = _require_auth_config()
    return config["userPoolId"]


def _identity_pool_role_arn(identity_pool_id: str, region: str) -> str:
    resp = boto3.client("cognito-identity", region_name=region).get_identity_pool_roles(
        IdentityPoolId=identity_pool_id
    )
    role_arn = resp.get("Roles", {}).get("authenticated", "")
    if not role_arn:
        raise HTTPException(
            status_code=400,
            detail="Identity pool does not have an authenticated role configured.",
        )
    return role_arn


def _normalize_actions(actions) -> List[str]:
    if isinstance(actions, list):
        return actions
    if isinstance(actions, str):
        return [actions]
    return []


def _normalize_resources(resources) -> List[str]:
    if isinstance(resources, list):
        return resources
    if isinstance(resources, str):
        return [resources]
    return []


def _is_public_principal(principal) -> bool:
    if principal == "*":
        return True
    if isinstance(principal, dict):
        aws = principal.get("AWS")
        if aws == "*":
            return True
        if isinstance(aws, list) and "*" in aws:
            return True
    return False


def _action_matches(actions: List[str], targets: List[str]) -> bool:
    for action in actions:
        if action in ("*", "s3:*"):
            return True
        if action.endswith("*"):
            prefix = action[:-1]
            if any(t.startswith(prefix) for t in targets):
                return True
        if action in targets:
            return True
    return False


def _get_bucket_policy(bucket_name: str, region: str) -> Optional[Dict[str, Any]]:
    s3_client = boto3.client("s3", region_name=region)
    try:
        resp = s3_client.get_bucket_policy(Bucket=bucket_name)
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") == "NoSuchBucketPolicy":
            return None
        raise
    return json.loads(resp["Policy"])


def _bucket_policy_plan(bucket_name: str, region: str) -> Dict[str, Any]:
    public_actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    bucket_arn = f"arn:aws:s3:::{bucket_name}"
    auth_config_arn = f"{bucket_arn}/{AUTH_CONFIG_KEY}"

    policy = _get_bucket_policy(bucket_name, region) or {"Version": "2012-10-17", "Statement": []}
    statements = policy.get("Statement", [])
    if isinstance(statements, dict):
        statements = [statements]

    new_statements = []
    removed_public = False
    public_access_detected = False
    deny_public_detected = False

    for stmt in statements:
        effect = stmt.get("Effect")
        principal = stmt.get("Principal")
        actions = _normalize_actions(stmt.get("Action"))
        resources = _normalize_resources(stmt.get("Resource"))

        if effect == "Deny" and _is_public_principal(principal):
            if _action_matches(actions, public_actions):
                if any(r.startswith(bucket_arn) for r in resources):
                    deny_public_detected = True

        if effect == "Allow" and _is_public_principal(principal):
            if _action_matches(actions, public_actions):
                public_access_detected = True
                is_auth_config_only = (
                    set(actions) == {"s3:GetObject"}
                    and set(resources) == {auth_config_arn}
                )
                if not is_auth_config_only:
                    removed_public = True
                    continue

        new_statements.append(stmt)

    allow_public_auth = {
        "Sid": "AllowPublicReadAuthConfig",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": auth_config_arn,
    }

    if not any(
        stmt.get("Effect") == "Allow"
        and _is_public_principal(stmt.get("Principal"))
        and "s3:GetObject" in _normalize_actions(stmt.get("Action"))
        and auth_config_arn in _normalize_resources(stmt.get("Resource"))
        for stmt in new_statements
    ):
        new_statements.append(allow_public_auth)

    new_policy = {"Version": policy.get("Version", "2012-10-17"), "Statement": new_statements}
    changes = removed_public or new_policy != policy

    return {
        "current_policy": policy,
        "new_policy": new_policy,
        "changes": changes,
        "public_access_detected": public_access_detected,
        "deny_public_detected": deny_public_detected,
    }


def _apply_bucket_policy(bucket_name: str, region: str) -> Dict[str, Any]:
    plan = _bucket_policy_plan(bucket_name, region)
    if plan["changes"]:
        boto3.client("s3", region_name=region).put_bucket_policy(
            Bucket=bucket_name,
            Policy=json.dumps(plan["new_policy"]),
        )
    return plan


def _role_policy_document(bucket_name: str) -> Dict[str, Any]:
    bucket_arn = f"arn:aws:s3:::{bucket_name}"
    return {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["s3:ListBucket"],
                "Resource": [bucket_arn],
            },
            {
                "Effect": "Allow",
                "Action": ["s3:GetObject", "s3:PutObject"],
                "Resource": [f"{bucket_arn}/*"],
            },
        ],
    }


def _policy_equal(a: Dict[str, Any], b: Dict[str, Any]) -> bool:
    return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


def _get_role_name(role_arn: str) -> str:
    if role_arn:
        return role_arn.split("/")[-1]
    return ""


def _role_policy_plan(role_name: str, bucket_name: str, region: str) -> Dict[str, Any]:
    iam = boto3.client("iam", region_name=region)
    desired = _role_policy_document(bucket_name)
    policy_name = f"{role_name}-bucket-access"

    try:
        resp = iam.get_role_policy(RoleName=role_name, PolicyName=policy_name)
        current = resp.get("PolicyDocument", {})
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") == "NoSuchEntity":
            current = None
        else:
            raise

    would_change = current is None or not _policy_equal(current, desired)
    return {"policy_name": policy_name, "desired": desired, "current": current, "changes": would_change}


def _apply_role_policy(role_name: str, bucket_name: str, region: str) -> Dict[str, Any]:
    plan = _role_policy_plan(role_name, bucket_name, region)
    if plan["changes"]:
        boto3.client("iam", region_name=region).put_role_policy(
            RoleName=role_name,
            PolicyName=plan["policy_name"],
            PolicyDocument=json.dumps(plan["desired"]),
        )
    return plan


@app.get("/")
def index():
    return FileResponse(str(FRONTEND_DIR / "index.html"))


@app.get("/org.html")
def org_page():
    return FileResponse(str(FRONTEND_DIR / "org.html"))


app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")


@app.get("/api/health")
def health():
    missing = _missing_env_vars()
    if missing:
        return {
            "ok": False,
            "message": f"Missing required environment variables: {', '.join(missing)}.",
        }
    cred_msg = _aws_credentials_ok(AWS_REGION or "")
    if cred_msg:
        return {"ok": False, "message": cred_msg}
    bucket_msg = _bucket_access_ok(BUCKET_NAME or "", AWS_REGION or "")
    if bucket_msg:
        return {"ok": False, "message": bucket_msg}
    return {"ok": True}


@app.get("/api/config")
def config():
    return {
        "bucketName": BUCKET_NAME,
        "bucketRootTemplate": _bucket_root_template(),
        "region": AWS_REGION,
    }


@app.get("/api/orgs")
def list_orgs():
    return {"orgs": s3.list_orgs()}


@app.get("/api/users")
def list_all_users():
    users = cognito.list_users(_user_pool_id())
    return {"users": users}


@app.get("/api/orgs/{org}/users")
def list_org_users(org: str):
    all_users = cognito.list_users(_user_pool_id())
    users_json = s3.get_users_json(org)
    if not users_json:
        return {"org": org, "users": []}

    mapped = []
    for u in users_json.get("users", []):
        key = (u.get("username") or u.get("email") or "").lower()
        match = None
        for cu in all_users:
            if (cu.get("preferred_username") or "").lower() == key or (
                cu.get("email") or ""
            ).lower() == key or (cu.get("username") or "").lower() == key:
                match = cu
                break
        mapped.append({"profile": u, "cognito": match})

    return {"org": org, "users": mapped}


@app.post("/api/orgs/{org}/users")
def add_user(org: str, payload: UserInput):
    if payload.org.lower() != org.lower():
        raise HTTPException(status_code=400, detail="Org mismatch")

    user_pool_id = _user_pool_id()

    s3.ensure_org_prefix(org)

    username = _normalize_username(payload.name)
    created = True
    try:
        cognito.add_user(
            user_pool_id,
            username=username,
            name=payload.name,
            email=payload.email,
            password=payload.password,
        )
    except cognito.cognito_idp.exceptions.UsernameExistsException:
        created = False
        cognito.update_password(user_pool_id, username, payload.password)
    except Exception as e:
        if hasattr(e, "response"):
            code = e.response.get("Error", {}).get("Code", "")
            message = e.response.get("Error", {}).get("Message", "")
            if code == "InvalidPasswordException":
                raise HTTPException(status_code=400, detail=message)
            raise HTTPException(status_code=400, detail=f"{code}: {message}")
        raise HTTPException(status_code=400, detail=str(e))

    users_json = s3.get_users_json(org)
    if not users_json:
        users_json = {
            "bucket_root": f"https://{BUCKET_NAME}.s3.amazonaws.com/{org}/",
            "org": org,
            "users": [],
            "updated_at": _now_iso(),
        }

    entry = {
        "name": payload.name,
        "email": payload.email,
        "username": username.lower(),
        "password": payload.password,
    }

    users_json["users"] = [
        u for u in users_json["users"] if (u.get("username") or "").lower() != entry["username"]
    ]
    users_json["users"].append(entry)
    users_json["updated_at"] = _now_iso()
    s3.put_users_json(org, users_json)

    return {"ok": True, "created": created}


@app.delete("/api/orgs/{org}/users/{username}")
def delete_user(org: str, username: str):
    cognito.delete_user(_user_pool_id(), username)

    users_json = s3.get_users_json(org)
    if users_json:
        users_json["users"] = [
            u
            for u in users_json.get("users", [])
            if (u.get("username") or "").lower() != username.lower()
        ]
        users_json["updated_at"] = _now_iso()
        s3.put_users_json(org, users_json)

    return {"ok": True}


@app.put("/api/orgs/{org}/users/{username}/password")
def update_password(org: str, username: str, payload: PasswordInput):
    cognito.update_password(_user_pool_id(), username, payload.password)
    users_json = s3.get_users_json(org)
    if users_json:
        for u in users_json.get("users", []):
            if (u.get("username") or "").lower() == username.lower():
                u["password"] = payload.password
        users_json["updated_at"] = _now_iso()
        s3.put_users_json(org, users_json)
    return {"ok": True}


@app.get("/api/auth_config")
def get_auth_config():
    existing = _get_auth_config_from_bucket()
    if existing:
        return existing
    raise HTTPException(status_code=404, detail="auth_config.json not found in bucket.")


@app.post("/api/auth_config/sync")
def sync_auth_config():
    missing = _missing_env_vars()
    if missing:
        raise HTTPException(
            status_code=400,
            detail=f"Missing required environment variables: {', '.join(missing)}.",
        )
    cred_msg = _aws_credentials_ok(AWS_REGION or "")
    if cred_msg:
        raise HTTPException(status_code=400, detail=cred_msg)
    bucket_msg = _bucket_access_ok(BUCKET_NAME or "", AWS_REGION or "")
    if bucket_msg:
        return JSONResponse(status_code=400, content=_setup_instructions())

    auth_config = _get_auth_config_from_bucket()
    if not auth_config:
        return JSONResponse(status_code=400, content=_setup_instructions())

    required = ["identityPoolId"]
    missing_fields = [key for key in required if not auth_config.get(key)]
    if missing_fields:
        raise HTTPException(
            status_code=400,
            detail=f"auth_config.json missing fields: {', '.join(missing_fields)}.",
        )

    identity_pool_id = auth_config["identityPoolId"]
    role_arn = _identity_pool_role_arn(identity_pool_id, AWS_REGION or "")
    role_name = _get_role_name(role_arn)

    bucket_plan = _apply_bucket_policy(BUCKET_NAME or "", AWS_REGION or "")
    role_plan = _apply_role_policy(role_name, BUCKET_NAME or "", AWS_REGION or "")

    return {
        "ok": True,
        "bucketPolicyChanged": bucket_plan["changes"],
        "rolePolicyChanged": role_plan["changes"],
        "roleName": role_name,
        "publicAccessDetected": bucket_plan["public_access_detected"],
    }


@app.get("/api/password_policy")
def get_password_policy():
    policy = cognito.get_password_policy(_user_pool_id())
    return PasswordPolicyOutput(
        minimumLength=policy.get("MinimumLength", 0),
        requireUppercase=policy.get("RequireUppercase", False),
        requireLowercase=policy.get("RequireLowercase", False),
        requireNumbers=policy.get("RequireNumbers", False),
        requireSymbols=policy.get("RequireSymbols", False),
    )


@app.get("/api/orgs/{org}/sites")
def get_sites(org: str):
    sites = s3.get_sites_json(org)
    if sites is None:
        return {"org": org, "sites_json": None}
    return {"org": org, "sites_json": sites}


@app.put("/api/orgs/{org}/sites")
def put_sites(org: str, payload: SitesPayload):
    s3.ensure_org_prefix(org)
    s3.put_sites_json(org, payload.sites_json)
    return {"ok": True}


@app.post("/api/orgs/{org}/sites/upload")
def upload_sites(org: str, file: UploadFile = File(...)):
    if not file.filename.endswith(".json"):
        raise HTTPException(status_code=400, detail="sites.json upload must be a .json file")
    content = file.file.read()
    try:
        sites_data = json.loads(content.decode("utf-8"))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")
    s3.ensure_org_prefix(org)
    s3.put_sites_json(org, sites_data)
    return {"ok": True}


@app.post("/api/orgs/{org}/ghosts")
def upload_ghost_image(
    org: str,
    site_id: str = Form(...),
    orientation: str = Form(...),
    image: UploadFile = File(...),
):
    if not site_id:
        raise HTTPException(status_code=400, detail="site_id is required")
    if orientation not in ("portrait", "landscape"):
        raise HTTPException(status_code=400, detail="orientation must be portrait or landscape")
    content = image.file.read()
    original = image.filename or "image"
    stem, dot, ext = original.rpartition(".")
    ext = f".{ext}" if dot else ""
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    base = _sanitize_filename(stem or "image")
    prefix = f"{org}/{site_id}/"
    existing = set(s3.list_keys(prefix))
    index = 1
    while True:
        candidate = f"{stamp}-{base}-{index}{ext}"
        key = f"{prefix}{candidate}"
        if key not in existing:
            break
        index += 1
    s3.upload_ghost_image(org, site_id, candidate, content, content_type=image.content_type)
    return {
        "ok": True,
        "key": key,
        "relative_path": f"{site_id}/{candidate}",
    }


@app.post("/api/orgs/{org}/provision")
def provision_org(org: str, bucket: Optional[str] = None):
    """Ensure org prefix, telemetry/{org}/ prefix, and the telemetry lifecycle rule exist.

    Idempotent — safe to call on every "Use Org" action whether the org is new
    or already exists. Returns what was created vs already in place.

    The optional `bucket` query parameter overrides the server's configured
    FOMOMON_BUCKET for this call only. Useful for testing against a throwaway
    bucket without restarting the server.
    """
    svc = S3Service(bucket_name=bucket, region=AWS_REGION or "") if bucket else s3
    effective_bucket = bucket or BUCKET_NAME
    svc.ensure_org_prefix(org)
    svc.ensure_telemetry_prefix(org)
    lc = svc.ensure_telemetry_lifecycle_rule()
    return {
        "ok": True,
        "org": org,
        "bucket": effective_bucket,
        "lifecycle_rule_created": lc["created"],
        "lifecycle_rules": lc["rules"],
    }


@app.get("/api/orgs/{org}/telemetry")
def get_telemetry(org: str, days: int = 7):
    """Fetch and merge telemetry events for the given org (last `days` days)."""
    result = s3.list_telemetry_events(org, days=days)
    return result


@app.delete("/api/orgs/{org}/telemetry")
def delete_telemetry(org: str):
    """Delete all telemetry objects for the given org under telemetry/{org}/."""
    count = s3.delete_telemetry(org)
    return {"ok": True, "deleted": count}


@app.get("/api/s3")
def presign_s3(key: str):
    if not key:
        raise HTTPException(status_code=400, detail="key is required")
    if key.startswith("/"):
        key = key[1:]
    url = s3.s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET_NAME, "Key": key},
        ExpiresIn=3600,
    )
    return RedirectResponse(url)
