#!/usr/bin/env bash
# admin/tests/unit/telemetry_lifecycle.sh
#
# End-to-end test: verifies that POST /api/orgs/{org}/provision sets a
# lifecycle rule scoped to "telemetry/" only, and that rule does NOT cover
# org data at {org}/.
#
# Usage:
#   bash admin/tests/unit/telemetry_lifecycle.sh
#
# The script creates a fresh test bucket, then calls the admin API (assumed
# running at http://localhost:8090). Start the server first:
#
#   cd admin
#   FOMOMON_BUCKET=<bucket-name> AWS_REGION=ap-south-1 \
#     uvicorn backend.main:app --port 8090
#
# The server must be running against the SAME bucket this script creates.
# Pass the pre-created bucket name via FOMOMON_BUCKET to reuse one:
#
#   FOMOMON_BUCKET=my-existing-bucket bash admin/tests/unit/telemetry_lifecycle.sh
#
# Requirements: aws-cli v2, jq, curl

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults — override via env vars if needed
# ---------------------------------------------------------------------------

REGION="${AWS_REGION:-ap-south-1}"
ADMIN_URL="${ADMIN_URL:-http://localhost:8090}"

# Create a new timestamped test bucket unless the caller already provided one.
if [[ -z "${FOMOMON_BUCKET:-}" ]]; then
  FOMOMON_BUCKET="fomomon-lc-test-$(date +%Y%m%d%H%M%S)"
  CREATE_BUCKET=1
else
  CREATE_BUCKET=0
fi

BUCKET="$FOMOMON_BUCKET"

# Use a timestamped org name so repeated runs don't collide and are easy to
# identify in S3 and the admin UI.
ORG="lctest-$(date +%Y%m%d%H%M%S)"
PERMANENT_KEY="${ORG}/permanent_file.md"
TELEMETRY_KEY="telemetry/${ORG}/temp_file.md"

# ---------------------------------------------------------------------------
# Colours / helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()   { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗  FAIL:${NC} $*" >&2; exit 1; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${CYAN}→${NC} $*"; }
header() { echo -e "\n${BOLD}=== $* ===${NC}"; }

# ---------------------------------------------------------------------------
# Cleanup — always printed on exit so test keys are not left dangling
# ---------------------------------------------------------------------------

_cleanup() {
  echo
  echo -e "${YELLOW}Cleanup (run after 48-hour verification):${NC}"
  echo "  aws s3 rm s3://${BUCKET}/${PERMANENT_KEY} --region ${REGION}"
  echo "  aws s3 rm s3://${BUCKET}/${TELEMETRY_KEY} --region ${REGION}"
  echo "  # If this was a dedicated test bucket, delete the whole thing:"
  echo "  aws s3 rb s3://${BUCKET} --force --region ${REGION}"
}
trap _cleanup EXIT

# ---------------------------------------------------------------------------
# Step 0: dependencies + server liveness
# ---------------------------------------------------------------------------

header "0. Checking dependencies and server"
for tool in aws jq curl; do
  command -v "$tool" &>/dev/null || fail "Required tool not found: ${tool}"
done
pass "aws, jq, curl found"

# Fail fast with a clear message if the admin server is not reachable.
if ! curl -sf "${ADMIN_URL}/api/health" > /tmp/health_resp.json 2>/dev/null; then
  fail "Admin server not reachable at ${ADMIN_URL}.
       Start it first:
         cd admin
         FOMOMON_BUCKET=${BUCKET} AWS_REGION=${REGION} \\
           uvicorn backend.main:app --port 8090"
fi
HEALTH_OK=$(jq -r '.ok // false' /tmp/health_resp.json)
[[ "$HEALTH_OK" == "true" ]] \
  && pass "Admin server healthy at ${ADMIN_URL}" \
  || fail "Admin server at ${ADMIN_URL} reports not healthy: $(cat /tmp/health_resp.json)
           Check that FOMOMON_BUCKET and AWS credentials are set on the server."

info "Bucket : s3://${BUCKET} (region: ${REGION})"
info "Org    : ${ORG}"
info "API    : ${ADMIN_URL}"

# ---------------------------------------------------------------------------
# Step 1: create the test bucket (skipped if FOMOMON_BUCKET was pre-set)
# ---------------------------------------------------------------------------

header "1. Test bucket"

if [[ "$CREATE_BUCKET" -eq 1 ]]; then
  info "Creating s3://${BUCKET}"
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "$BUCKET" --region "$REGION" --no-cli-pager > /dev/null
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" \
      --no-cli-pager > /dev/null
  fi
  aws s3api put-public-access-block \
    --bucket "$BUCKET" --region "$REGION" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --no-cli-pager > /dev/null
  pass "Created: s3://${BUCKET}"
else
  pass "Reusing existing bucket: s3://${BUCKET}"
fi

# ---------------------------------------------------------------------------
# Step 2: create test files directly in the bucket via AWS CLI
# ---------------------------------------------------------------------------

header "2. Creating test objects in s3://${BUCKET}"

echo "Org data — this file MUST survive the telemetry lifecycle rule." \
  | aws s3 cp - "s3://${BUCKET}/${PERMANENT_KEY}" --region "$REGION" --quiet
pass "${PERMANENT_KEY}"

echo "Telemetry data — this file MUST be expired by the telemetry lifecycle rule." \
  | aws s3 cp - "s3://${BUCKET}/${TELEMETRY_KEY}" --region "$REGION" --quiet
pass "${TELEMETRY_KEY}"

# ---------------------------------------------------------------------------
# Step 2: call the admin API — this is the action under test
# ---------------------------------------------------------------------------

header "3. Calling POST /api/orgs/${ORG}/provision?bucket=${BUCKET}"
info "The bucket query param tells the server to target the test bucket, not its default."

HTTP_STATUS=$(curl -s -o /tmp/prov_resp.json -w "%{http_code}" \
  -X POST "${ADMIN_URL}/api/orgs/${ORG}/provision?bucket=${BUCKET}" \
  -H "Content-Type: application/json")

[[ "$HTTP_STATUS" -eq 200 ]] \
  || fail "Provision returned HTTP ${HTTP_STATUS}: $(cat /tmp/prov_resp.json)"

API_OK=$(jq -r '.ok // false' /tmp/prov_resp.json)
RULE_CREATED=$(jq -r '.lifecycle_rule_created // "unknown"' /tmp/prov_resp.json)
RESP_BUCKET=$(jq -r '.bucket // ""' /tmp/prov_resp.json)

[[ "$API_OK" == "true" ]] \
  && pass "API response: ok=true" \
  || fail "API returned ok=${API_OK}: $(cat /tmp/prov_resp.json)"

[[ "$RESP_BUCKET" == "$BUCKET" ]] \
  && pass "API operated on test bucket: ${RESP_BUCKET}" \
  || fail "API operated on wrong bucket: \"${RESP_BUCKET}\" (expected \"${BUCKET}\")"

if [[ "$RULE_CREATED" == "true" ]]; then
  pass "lifecycle_rule_created=true  (rule was newly written)"
elif [[ "$RULE_CREATED" == "false" ]]; then
  warn "lifecycle_rule_created=false  (rule already existed — idempotent)"
else
  warn "lifecycle_rule_created=${RULE_CREATED}"
fi

# ---------------------------------------------------------------------------
# Step 3: read the lifecycle config from S3 and verify scoping
# ---------------------------------------------------------------------------

header "4. Verifying lifecycle rule on s3://${BUCKET}"

LC=$(aws s3api get-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --output json) || fail "No lifecycle configuration found on bucket."

# Must have at least one rule with prefix "telemetry/".
TELEMETRY_RULE=$(echo "$LC" | jq '
  [.Rules[] |
    (.Filter.Prefix // .Filter.And.Prefix // .Prefix // "") as $p |
    select($p == "telemetry/") |
    {id: .ID, prefix: $p, status: .Status, expiry_days: .Expiration.Days}
  ]')

TELEMETRY_RULE_COUNT=$(echo "$TELEMETRY_RULE" | jq 'length')
[[ "$TELEMETRY_RULE_COUNT" -ge 1 ]] \
  && pass "Rule with prefix \"telemetry/\" exists (${TELEMETRY_RULE_COUNT} match(es))" \
  || fail "No rule found with prefix \"telemetry/\""

RULE_STATUS=$(echo "$TELEMETRY_RULE" | jq -r '.[0].status')
[[ "$RULE_STATUS" == "Enabled" ]] \
  && pass "Rule status: Enabled" \
  || fail "Rule status is \"${RULE_STATUS}\" — expected Enabled"

RULE_DAYS=$(echo "$TELEMETRY_RULE" | jq -r '.[0].expiry_days')
pass "Rule expiry: ${RULE_DAYS} day(s)"

# Critical: no rule may have a prefix that would match the permanent (org) key.
# A rule matches an object when the object key starts with the rule's prefix.
# An empty prefix matches everything — that would silently delete all org data.
DANGEROUS_RULES=$(echo "$LC" | jq --arg key "$PERMANENT_KEY" '
  [.Rules[] |
    (.Filter.Prefix // .Filter.And.Prefix // .Prefix // "") as $p |
    select($p == "" or ($p != "telemetry/" and ($key | startswith($p))))
  ]')

DANGEROUS_COUNT=$(echo "$DANGEROUS_RULES" | jq 'length')

if [[ "$DANGEROUS_COUNT" -gt 0 ]]; then
  fail "UNSAFE: ${DANGEROUS_COUNT} rule(s) would match \"${PERMANENT_KEY}\" — org data at risk:
$(echo "$DANGEROUS_RULES" | jq -c '.[]')"
else
  pass "No rule covers \"${PERMANENT_KEY}\" — org data is safe"
fi

echo
info "Full lifecycle config on bucket:"
echo "$LC" | jq '.Rules[] | {id: .ID, prefix: (.Filter.Prefix // .Filter.And.Prefix // .Prefix // "(empty=ALL)"), status: .Status, expiry_days: .Expiration.Days}'

# ---------------------------------------------------------------------------
# Step 4: verify both objects still exist immediately (no accidental delete)
# ---------------------------------------------------------------------------

header "5. Confirming both objects are present"

aws s3api head-object \
  --bucket "$BUCKET" --key "$PERMANENT_KEY" --region "$REGION" \
  --no-cli-pager > /dev/null 2>&1 \
  && pass "Permanent file present: ${PERMANENT_KEY}" \
  || fail "Permanent file already missing: ${PERMANENT_KEY}"

aws s3api head-object \
  --bucket "$BUCKET" --key "$TELEMETRY_KEY" --region "$REGION" \
  --no-cli-pager > /dev/null 2>&1 \
  && pass "Telemetry file present: ${TELEMETRY_KEY}" \
  || fail "Telemetry file already missing: ${TELEMETRY_KEY}"

# ---------------------------------------------------------------------------
# Step 5: print 48-hour verification commands
# ---------------------------------------------------------------------------
# S3 lifecycle minimum is 1 day. AWS evaluates rules once daily; actual
# deletion happens 24–48 h after eligibility. We cannot poll for this.
# ---------------------------------------------------------------------------

header "6. Manual verification (return in ~48 hours)"

echo
echo -e "${BOLD}Run these after ~48 hours to confirm expiry behaviour:${NC}"
echo
echo -e "  ${CYAN}# A. Telemetry file must be GONE (expect NoSuchKey / non-zero exit)${NC}"
echo "  aws s3api head-object \\"
echo "    --bucket  ${BUCKET} \\"
echo "    --key     ${TELEMETRY_KEY} \\"
echo "    --region  ${REGION}"
echo
echo -e "  ${CYAN}# B. Permanent org file must STILL EXIST (expect HTTP 200)${NC}"
echo "  aws s3api head-object \\"
echo "    --bucket  ${BUCKET} \\"
echo "    --key     ${PERMANENT_KEY} \\"
echo "    --region  ${REGION}"

# ---------------------------------------------------------------------------
# Manual command for the production fomomon bucket
# ---------------------------------------------------------------------------

echo
echo -e "${BOLD}To verify the lifecycle policy on the production fomomon bucket:${NC}"
echo
echo "  aws s3api get-bucket-lifecycle-configuration \\"
echo "    --bucket  fomomon \\"
echo "    --region  ${REGION} \\"
echo "    --output  json \\"
echo "  | jq '.Rules[] | {"
echo "      id:          .ID,"
echo "      prefix:      (.Filter.Prefix // .Filter.And.Prefix // .Prefix // \"(empty=ALL)\"),"
echo "      status:      .Status,"
echo "      expiry_days: .Expiration.Days"
echo "    }'"
echo
echo -e "  ${CYAN}# Expected: one entry with prefix=\"telemetry/\", expiry_days=90, status=\"Enabled\"${NC}"
echo -e "  ${CYAN}# No entry should have prefix=\"\" (empty) or any org name (t4gc, ncf, etc.)${NC}"

echo
echo -e "${GREEN}All structural checks passed.${NC}"
echo -e "Bucket: ${BOLD}s3://${BUCKET}${NC}"
echo -e "Test org: ${BOLD}${ORG}${NC}"
