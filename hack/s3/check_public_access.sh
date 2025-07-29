#!/bin/bash

# This script checks if a bucket has public write access via the following:
# 1. Public Access Block settings
# 2. Bucket Policy (for public write access)
# 3. Bucket ACL (for public write access)
# 4. Public Write Access (for public write access)
#
# NB a bucket ACL of the following is required and means admin has write access:
# {
#     "Owner": {
#         "ID": "some id"
#     },
#     "Grants": [
#         {
#             "Grantee": {
#                 "ID": "some id",
#                 "Type": "CanonicalUser"
#             },
#             "Permission": "FULL_CONTROL"
#         }
#     ]
# }
# 
# Usage:
# ./check_public_access.sh <bucket-name>
# Example:
# ./check_public_access.sh fomomon

BUCKET_NAME=$1

if [ -z "$BUCKET_NAME" ]; then
    echo "Usage: $0 <bucket-name>"
    exit 1
fi

echo "=== Checking Public Access for bucket: $BUCKET_NAME ==="
echo

# Check Public Access Block settings
echo "1. Public Access Block Settings:"
aws s3api get-public-access-block --bucket $BUCKET_NAME 2>/dev/null || echo "No public access block configured"
echo

# Check Bucket Policy
echo "2. Bucket Policy:"
aws s3api get-bucket-policy --bucket $BUCKET_NAME 2>/dev/null || echo "No bucket policy found"
echo

# Check Bucket ACL
echo "3. Bucket ACL:"
aws s3api get-bucket-acl --bucket $BUCKET_NAME
echo

# Check if bucket allows public write
echo "4. Public Write Access Analysis:"
echo "=================================="

# Check public access block
BLOCK_PUBLIC_ACLS=$(aws s3api get-public-access-block --bucket $BUCKET_NAME --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text 2>/dev/null || echo "false")
BLOCK_PUBLIC_POLICY=$(aws s3api get-public-access-block --bucket $BUCKET_NAME --query 'PublicAccessBlockConfiguration.BlockPublicPolicy' --output text 2>/dev/null || echo "false")

if [ "$BLOCK_PUBLIC_ACLS" = "false" ] && [ "$BLOCK_PUBLIC_POLICY" = "false" ]; then
    echo "WARNING: Public access is NOT blocked"
    echo "   - BlockPublicAcls: $BLOCK_PUBLIC_ACLS"
    echo "   - BlockPublicPolicy: $BLOCK_PUBLIC_POLICY"
else
    echo "Public access is blocked"
    echo "   - BlockPublicAcls: $BLOCK_PUBLIC_ACLS"
    echo "   - BlockPublicPolicy: $BLOCK_PUBLIC_POLICY"
fi

# Check bucket ACL for public grants
PUBLIC_GRANTS=$(aws s3api get-bucket-acl --bucket $BUCKET_NAME --query 'Grants[?Grantee.Type==`Group` && Grantee.URI==`http://acs.amazonaws.com/groups/global/AllUsers`]' --output text 2>/dev/null)

if [ -n "$PUBLIC_GRANTS" ]; then
    echo "WARNING: Bucket has public ACL grants"
    echo "   Public grants: $PUBLIC_GRANTS"
else
    echo "No public ACL grants found"
fi

# Check for public WRITE access specifically
POLICY_PUBLIC_WRITE=$(aws s3api get-bucket-policy --bucket $BUCKET_NAME --query 'Policy' --output text 2>/dev/null | grep -E '"Principal":\s*"\*".*"Action":\s*"s3:(Put|Delete|Create|Write)"' | head -1)

if [ -n "$POLICY_PUBLIC_WRITE" ]; then
    echo "WARNING: Bucket policy allows public access"
    echo "   Found Principal: * in policy"
else
    echo "No public access in bucket policy"
fi

echo
echo "=== Summary ==="
if [ "$BLOCK_PUBLIC_ACLS" = "false" ] || [ "$BLOCK_PUBLIC_POLICY" = "false" ] || [ -n "$PUBLIC_GRANTS" ] || [ -n "$POLICY_PUBLIC_WRITE" ]; then
    echo "BUCKET MAY HAVE PUBLIC WRITE ACCESS"
else
    echo "BUCKET APPEARS TO BE SECURE"
fi 