import json
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
        orgs = [p["Prefix"].rstrip("/") for p in prefixes]
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
        self, org: str, site_id: str, filename: str, content: bytes
    ) -> str:
        key = f"{org}/{site_id}/{filename}"
        self.s3.put_object(Bucket=self.bucket_name, Key=key, Body=content)
        return key

    def list_keys(self, prefix: str) -> List[str]:
        keys: List[str] = []
        paginator = self.s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=self.bucket_name, Prefix=prefix):
            for obj in page.get("Contents", []):
                keys.append(obj["Key"])
        return keys
