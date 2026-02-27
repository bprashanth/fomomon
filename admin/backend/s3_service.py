import json
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any, Optional

import boto3
from botocore.exceptions import ClientError


class S3Service:
    def __init__(self, bucket_name: str, region: str):
        self.bucket_name = bucket_name
        self.region = region
        self.s3 = boto3.client("s3", region_name=region)

    def list_orgs(self) -> List[str]:
        resp = self.s3.list_objects_v2(
            Bucket=self.bucket_name, Delimiter="/"
        )
        prefixes = resp.get("CommonPrefixes", [])
        # Exclude the top-level telemetry/ prefix — it is not an org.
        orgs = [p["Prefix"].rstrip("/") for p in prefixes if p["Prefix"] != "telemetry/"]
        return sorted(orgs)

    def ensure_org_prefix(self, org: str) -> None:
        key = f"{org}/"
        self.s3.put_object(Bucket=self.bucket_name, Key=key, Body=b"")

    def get_users_json(self, org: str) -> Optional[Dict[str, Any]]:
        key = f"{org}/users.json"
        try:
            resp = self.s3.get_object(Bucket=self.bucket_name, Key=key)
            body = resp["Body"].read().decode("utf-8")
            return json.loads(body)
        except self.s3.exceptions.NoSuchKey:
            return None
        except ClientError as e:
            if e.response.get("Error", {}).get("Code") in ("NoSuchKey", "404"):
                return None
            raise

    def put_users_json(self, org: str, users_data: Dict[str, Any]) -> None:
        key = f"{org}/users.json"
        body = json.dumps(users_data, indent=2)
        self.s3.put_object(
            Bucket=self.bucket_name,
            Key=key,
            Body=body.encode("utf-8"),
            ContentType="application/json",
        )

    def get_sites_json(self, org: str) -> Optional[Dict[str, Any]]:
        key = f"{org}/sites.json"
        try:
            resp = self.s3.get_object(Bucket=self.bucket_name, Key=key)
            body = resp["Body"].read().decode("utf-8")
            return json.loads(body)
        except self.s3.exceptions.NoSuchKey:
            return None
        except ClientError as e:
            if e.response.get("Error", {}).get("Code") in ("NoSuchKey", "404"):
                return None
            raise

    def put_sites_json(self, org: str, sites_data: Dict[str, Any]) -> None:
        key = f"{org}/sites.json"
        body = json.dumps(sites_data, indent=2)
        self.s3.put_object(
            Bucket=self.bucket_name,
            Key=key,
            Body=body.encode("utf-8"),
            ContentType="application/json",
        )

    def upload_ghost_image(
        self,
        org: str,
        site_id: str,
        filename: str,
        content: bytes,
        content_type: str | None = None,
    ) -> str:
        key = f"{org}/{site_id}/{filename}"
        extra = {}
        if content_type:
            extra["ContentType"] = content_type
        self.s3.put_object(Bucket=self.bucket_name, Key=key, Body=content, **extra)
        return key

    def list_keys(self, prefix: str) -> List[str]:
        keys: List[str] = []
        paginator = self.s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=self.bucket_name, Prefix=prefix):
            for obj in page.get("Contents", []):
                keys.append(obj["Key"])
        return keys

    def ensure_telemetry_prefix(self, org: str) -> None:
        """Create the telemetry/{org}/ placeholder key if it doesn't exist."""
        key = f"telemetry/{org}/"
        self.s3.put_object(Bucket=self.bucket_name, Key=key, Body=b"")

    def ensure_telemetry_lifecycle_rule(self, expiry_days: int = 90) -> bool:
        """Idempotently add a lifecycle rule expiring telemetry/ after expiry_days.

        Returns True if a new rule was written, False if one already existed.
        Uses PUT (replaces entire config), so existing rules are preserved.
        """
        prefix = "telemetry/"
        try:
            resp = self.s3.get_bucket_lifecycle_configuration(Bucket=self.bucket_name)
            rules = resp.get("Rules", [])
        except ClientError as e:
            if e.response.get("Error", {}).get("Code") == "NoSuchLifecycleConfiguration":
                rules = []
            else:
                raise

        # Check if a matching rule already exists (prefix + expiry + enabled).
        for rule in rules:
            f = rule.get("Filter", {})
            rule_prefix = f.get("Prefix", "") if isinstance(f, dict) else rule.get("Prefix", "")
            if (
                rule_prefix == prefix
                and rule.get("Status") == "Enabled"
                and rule.get("Expiration", {}).get("Days") == expiry_days
            ):
                return False  # Already in place — nothing to do.

        new_rule: Dict[str, Any] = {
            "ID": "expire-telemetry-90d",
            "Filter": {"Prefix": prefix},
            "Status": "Enabled",
            "Expiration": {"Days": expiry_days},
        }
        rules.append(new_rule)
        self.s3.put_bucket_lifecycle_configuration(
            Bucket=self.bucket_name,
            LifecycleConfiguration={"Rules": rules},
        )
        return True

    def list_telemetry_events(
        self, org: str, days: int = 7, max_bytes: int = 1_000_000
    ) -> Dict[str, Any]:
        """Fetch and merge telemetry events for org from the last `days` days.

        Lists objects under telemetry/{org}/, fetches up to max_bytes (newest
        first), merges all events[] arrays, and returns them sorted by
        timestamp descending.
        """
        prefix = f"telemetry/{org}/"
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)

        paginator = self.s3.get_paginator("list_objects_v2")
        objects = []
        for page in paginator.paginate(Bucket=self.bucket_name, Prefix=prefix):
            for obj in page.get("Contents", []):
                if obj["Key"] == prefix:  # skip placeholder key
                    continue
                if obj["LastModified"] >= cutoff:
                    objects.append(obj)

        # Newest files first so we reach the 1 MB cap from the most recent end.
        objects.sort(key=lambda o: o["LastModified"], reverse=True)

        events: List[Dict[str, Any]] = []
        bytes_fetched = 0
        files_fetched = 0

        for obj in objects:
            if bytes_fetched >= max_bytes:
                break
            try:
                resp = self.s3.get_object(Bucket=self.bucket_name, Key=obj["Key"])
                body = resp["Body"].read()
                bytes_fetched += len(body)
                files_fetched += 1
                data = json.loads(body.decode("utf-8"))
                for event in data.get("events", []):
                    event["_userId"] = data.get("userId")
                    event["_appVersion"] = data.get("appVersion")
                    events.append(event)
            except Exception:
                continue

        events.sort(key=lambda e: e.get("timestamp", ""), reverse=True)

        return {
            "events": events,
            "files_fetched": files_fetched,
            "bytes_fetched": bytes_fetched,
        }
