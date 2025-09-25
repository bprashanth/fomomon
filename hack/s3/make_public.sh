#!/bin/bash

# A simple shell script to apply a public read policy to a specific S3 object.
# This script requires two command-line arguments: the bucket name and the object key.
# Example usage: ./apply_s3_policy.sh fomomon auth_config.json

# Check if the correct number of arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <bucket-name> <object-key>; where object-key is rel path to the file itself, eg foo/bar/file.json"
    exit 1
fi

BUCKET_NAME="$1"
OBJECT_KEY="$2"

# Construct the JSON policy document
POLICY_JSON=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/${OBJECT_KEY}"
        }
    ]
}
EOF
)

# Apply the bucket policy using the AWS CLI
echo "Applying public read policy to s3://${BUCKET_NAME}/${OBJECT_KEY}..."
aws s3api put-bucket-policy \
    --bucket "${BUCKET_NAME}" \
    --policy "${POLICY_JSON}"

if [ $? -eq 0 ]; then
    echo "Policy applied successfully!"
else
    echo "Error applying policy. Please check your AWS credentials and bucket permissions."
fi
