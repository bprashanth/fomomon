import json
import os
from typing import List, Optional, Dict, Any
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
import re

from .cognito_service import CognitoService
from .s3_service import S3Service


APP_NAME = os.getenv("APP_NAME", "fomomon")
APP_TYPE = os.getenv("APP_TYPE", "phone")
AWS_REGION = os.getenv("AWS_REGION", "ap-south-1")
BUCKET_NAME = os.getenv("FOMOMON_BUCKET", "fomomon")
AUTO_CREATE_POOLS = os.getenv("AUTO_CREATE_POOLS", "false").lower() == "true"

app = FastAPI(title="Fomomon Admin", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"] ,
    allow_headers=["*"],
)

cognito = CognitoService(
    app_name=APP_NAME,
    app_type=APP_TYPE,
    region=AWS_REGION,
    bucket_name=BUCKET_NAME,
)

s3 = S3Service(bucket_name=BUCKET_NAME, region=AWS_REGION)


class UserInput(BaseModel):
    org: str = Field(..., min_length=1)
    name: str
    email: str
    password: str


class PasswordInput(BaseModel):
    password: str


class AuthConfigOutput(BaseModel):
    userPoolId: str
    clientId: str
    identityPoolId: str
    region: str


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

def _get_app_info_or_create():
    info = cognito.get_app_info()
    if info is None:
        if not AUTO_CREATE_POOLS:
            raise HTTPException(
                status_code=400,
                detail="Cognito pools not found. Set AUTO_CREATE_POOLS=true to create.",
            )
        info = cognito.ensure_app_setup(write_access=True)
    return info


@app.get("/")
def index():
    return FileResponse("admin/frontend/index.html")


@app.get("/org.html")
def org_page():
    return FileResponse("admin/frontend/org.html")


app.mount("/static", StaticFiles(directory="admin/frontend"), name="static")


@app.get("/api/orgs")
def list_orgs():
    return {"orgs": s3.list_orgs()}


@app.get("/api/users")
def list_all_users():
    info = _get_app_info_or_create()
    users = cognito.list_users(info.user_pool_id)
    return {"users": users}


@app.get("/api/orgs/{org}/users")
def list_org_users(org: str):
    info = _get_app_info_or_create()
    all_users = cognito.list_users(info.user_pool_id)
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

    info = _get_app_info_or_create()

    s3.ensure_org_prefix(org)

    username = _normalize_username(payload.name)
    created = True
    try:
        cognito.add_user(
            info.user_pool_id,
            username=username,
            name=payload.name,
            email=payload.email,
            password=payload.password,
        )
    except cognito.cognito_idp.exceptions.UsernameExistsException:
        created = False
        cognito.update_password(info.user_pool_id, username, payload.password)
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
    info = _get_app_info_or_create()
    cognito.delete_user(info.user_pool_id, username)

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
    info = _get_app_info_or_create()
    cognito.update_password(info.user_pool_id, username, payload.password)
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
    info = cognito.get_app_info()
    if info is None:
        raise HTTPException(status_code=404, detail="Cognito app not found")
    return AuthConfigOutput(
        userPoolId=info.user_pool_id,
        clientId=info.client_id,
        identityPoolId=info.identity_pool_id,
        region=AWS_REGION,
    )


@app.post("/api/auth_config/sync")
def sync_auth_config():
    info = cognito.get_app_info()
    if info is None:
        raise HTTPException(status_code=404, detail="Cognito app not found")

    auth_config = {
        "userPoolId": info.user_pool_id,
        "clientId": info.client_id,
        "identityPoolId": info.identity_pool_id,
        "region": AWS_REGION,
    }
    key = "auth_config.json"
    s3.s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=json.dumps(auth_config, indent=2).encode("utf-8"),
        ContentType="application/json",
    )
    return {"ok": True, "auth_config": auth_config}


@app.get("/api/password_policy")
def get_password_policy():
    info = _get_app_info_or_create()
    policy = cognito.get_password_policy(info.user_pool_id)
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
    s3.upload_ghost_image(org, site_id, candidate, content)
    return {
        "ok": True,
        "key": key,
        "relative_path": f"{site_id}/{candidate}",
    }
