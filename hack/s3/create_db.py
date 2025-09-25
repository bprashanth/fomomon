#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Combine FOMO sessions from S3 into a single db.json (or custom path).

Usage:
  python combine_sessions.py \
    --root-bucket s3://fomomon/ncf/ \
    --sites-config ./sites.json \
    --output-path ./db.json

Design:
- SitesConfig: loads sites.json, normalizes site ids, looks up question text
- SessionsDownloader: downloads *.json sessions from <root>/sessions/ to a temp dir
- SessionsCombiner: reads sessions, enriches with question text, writes combined JSON
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import posixpath
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Tuple

import boto3
from botocore.exceptions import ClientError

# -------------------------
# Logging
# -------------------------

LOG = logging.getLogger("combine_sessions")
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(logging.Formatter("[%(levelname)s] %(message)s"))
LOG.addHandler(handler)
LOG.setLevel(logging.INFO)


# -------------------------
# Helpers
# -------------------------

_S3_URL_RE = re.compile(r"^s3://([^/]+)/?(.*)$")
_DEFAULT_QUESTION_LOOKUP = {"q1":"What animals did you see?", "q2": "Was there litter?"}

def parse_s3_url(url: str) -> Tuple[str, str]:
    """Parse s3://bucket/prefix into (bucket, key_prefix)."""
    m = _S3_URL_RE.match(url.strip())
    if not m:
        raise ValueError(f"Invalid S3 URL: {url!r}")
    bucket = m.group(1)
    key = m.group(2) or ""
    key = key.strip("/")
    return bucket, key


def ensure_trailing_slash(p: str) -> str:
    return p if p.endswith("/") else p + "/"


def read_json_file(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json_file(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


# -------------------------
# SitesConfig
# -------------------------

class SiteNotFound(Exception):
    """Raised when a site id isn't found after normalization."""


@dataclass
class SiteInfo:
    id: str
    location: Dict[str, Any]
    survey_by_id: Dict[str, Dict[str, Any]]  # qid -> survey entry
    raw: Dict[str, Any]  # original site object


class SitesConfig:
    """
    Handles sites.json:
      - normalizes site ids
      - provides lookup of question text by (site_id, questionId)
    """

    def __init__(self, sites_json_path: str):
        self._raw = read_json_file(sites_json_path)
        self.bucket_root: str = self._raw.get("bucket_root", "")
        sites = self._raw.get("sites", [])
        if not isinstance(sites, list) or not sites:
            raise ValueError("sites.json is missing a non-empty 'sites' list")

        self._sites_by_norm: Dict[str, SiteInfo] = {}

        for s in sites:
            site_id = s.get("id")
            if not site_id:
                LOG.warning("Skipping site with missing 'id': %s", s)
                continue
            norm = self.normalize_site_id(site_id)
            survey = s.get("survey", []) or []
            survey_by_id = {q.get("id"): q for q in survey if q.get("id")}
            self._sites_by_norm[norm] = SiteInfo(
                id=site_id,
                location=s.get("location", {}),
                survey_by_id=survey_by_id,
                raw=s,
            )

    _YEAR_PREFIX = re.compile(r"^\s*(19|20)\d{2}[_-]+")  # e.g., 2024_J12_R1 -> strip "2024_"
    _NON_ALNUM = re.compile(r"[^A-Za-z0-9]")

    @classmethod
    def normalize_site_id(cls, site_id: str) -> str:
        """
        Normalization heuristic to map variants to canonical ids found in sites.json.
        Examples:
          "2024_J12_R1" -> "J12R1"
          "J12R1"       -> "J12R1"
          "P1_R2"       -> "P1R2"
        """
        s = site_id or ""
        s = s.strip()
        s = cls._YEAR_PREFIX.sub("", s)  # drop leading year+sep
        s = s.replace("_", "")           # remove underscores
        s = s.replace("-", "")           # remove dashes
        return s

    def get_question_text(self, site_id: str, question_id: str) -> str:
        """
        Return the plaintext question for (site_id, question_id).
        Raises SiteNotFound if the normalized site id isn't present.
        Returns empty string if the question id isn't in the site's survey.
        """
        norm = self.normalize_site_id(site_id)
        site = self._sites_by_norm.get(norm)
        if not site:
            raise SiteNotFound(f"Site not found in sites.json after normalization: {site_id} (norm={norm})")

        q = site.survey_by_id.get(question_id)
        return q.get("question", "") if q else ""


# -------------------------
# SessionsDownloader
# -------------------------

class SessionsDownloader:
    """
    Downloads session JSONs from s3://<bucket>/<prefix>/sessions/ to a temp dir.
    """

    def __init__(self, root_bucket_url: str, s3_client=None):
        self.bucket, self.prefix = parse_s3_url(root_bucket_url)
        self.prefix = ensure_trailing_slash(self.prefix) if self.prefix else ""
        self.s3 = s3_client or boto3.client("s3")

    def _sessions_prefix(self) -> str:
        # Always look under "<prefix>sessions/"
        return posixpath.join(self.prefix, "sessions/") if self.prefix else "sessions/"

    def list_session_keys(self) -> List[str]:
        prefix = self._sessions_prefix()
        keys: List[str] = []
        continuation_token: Optional[str] = None
        while True:
            kwargs = {"Bucket": self.bucket, "Prefix": prefix}
            if continuation_token:
                kwargs["ContinuationToken"] = continuation_token
            resp = self.s3.list_objects_v2(**kwargs)
            for obj in resp.get("Contents", []):
                k = obj["Key"]
                if k.endswith(".json"):
                    keys.append(k)
            if resp.get("IsTruncated"):
                continuation_token = resp.get("NextContinuationToken")
            else:
                break
        return keys

    def download_to_tempdir(self) -> str:
        tmpdir = tempfile.mkdtemp(prefix="fomo_sessions_")
        keys = self.list_session_keys()
        if not keys:
            LOG.warning("No session files found under s3://%s/%s", self.bucket, self._sessions_prefix())
            return tmpdir
        LOG.info("Found %d session files. Downloading...", len(keys))
        for k in keys:
            fname = os.path.basename(k)
            out_path = os.path.join(tmpdir, fname)
            try:
                self.s3.download_file(self.bucket, k, out_path)
            except ClientError as e:
                LOG.error("Failed to download s3://%s/%s: %s", self.bucket, k, e)
        return tmpdir


# -------------------------
# SessionsCombiner
# -------------------------

class SessionsCombiner:
    """
    Combines session JSON files into a single list (db.json). Enriches responses
    with plaintext 'question' per sites.json.
    """

    def __init__(self, sites_config: SitesConfig):
        self.sites = sites_config

    def _enrich_session(self, session: Dict[str, Any]) -> Dict[str, Any]:
        site_id = session.get("siteId", "")
        responses = session.get("responses", []) or []

        enriched = []
        for item in responses:
            qid = item.get("questionId", "")
            try:
                qtext = self.sites.get_question_text(site_id, qid)
            except SiteNotFound as e:
                # Caller asked us to log a warning but keep the session.
                LOG.warning(str(e))
                qtext = _DEFAULT_QUESTION_LOOKUP[qid]
            enriched.append({
                **item,
                "question": qtext
            })

        session["responses"] = enriched
        return session

    def combine_dir(self, sessions_dir: str) -> List[Dict[str, Any]]:
        combined: List[Dict[str, Any]] = []
        for entry in sorted(os.listdir(sessions_dir)):
            if not entry.endswith(".json"):
                continue
            path = os.path.join(sessions_dir, entry)
            try:
                data = read_json_file(path)
                data = self._enrich_session(data)
                combined.append(data)
            except Exception as e:
                LOG.error("Skipping %s due to error: %s", path, e)
        return combined


# -------------------------
# CLI
# -------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Combine FOMO sessions into a single db.json")
    parser.add_argument("--root-bucket", required=True, help="Root S3 bucket (e.g., s3://fomomon/ncf/)")
    parser.add_argument("--sites-config", required=True, help="Path to sites.json")
    parser.add_argument("--output-path", default="db.json", help="Path to write combined JSON (default: db.json)")
    parser.add_argument("--keep-temp", action="store_true", help="Keep the downloaded temp dir (for debugging)")
    args = parser.parse_args(argv)

    # Load sites config
    try:
        sites = SitesConfig(args.sites_config)
    except Exception as e:
        LOG.error("Failed to load sites config: %s", e)
        return 2

    # Download sessions
    downloader = SessionsDownloader(args.root_bucket)
    tmpdir = downloader.download_to_tempdir()

    try:
        # Combine
        combiner = SessionsCombiner(sites)
        combined = combiner.combine_dir(tmpdir)
        LOG.info("Combined %d sessions.", len(combined))
        write_json_file(args.output_path, combined)
        LOG.info("Wrote %s", args.output_path)
    finally:
        if args.keep_temp:
            LOG.info("Keeping temp dir: %s", tmpdir)
        else:
            shutil.rmtree(tmpdir, ignore_errors=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
