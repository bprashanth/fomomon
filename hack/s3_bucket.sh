#!/bin/bash

# This script runs standalone and creates the fomomon bucket. 
# It assumes the aws cli has already been authenticated with the cloud. 
# Usage: 
#     ./s3_bucket.sh --bucket_name fomomon --create
#     ./s3_bucket.sh --bucket_name fomomon --path foo/bar --file path/to/file.jpg

# Default values
BUCKET_NAME=""
CREATE_BUCKET=false
BUCKET_PATH=""
FILE_PATH=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket_name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --create)
            CREATE_BUCKET=true
            shift
            ;;
        --path)
            BUCKET_PATH="$2"
            shift 2
            ;;
        --file)
            FILE_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage:"
            echo "  $0 --bucket_name <name> --create"
            echo "  $0 --bucket_name <name> --path <path> --file <FILE_PATH>"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$BUCKET_NAME" ]]; then
    echo "Error: --bucket_name is required"
    exit 1
fi

if [[ "$CREATE_BUCKET" == true ]]; then
    echo "Creating bucket: $BUCKET_NAME"
    
    # Create the bucket (replace with your bucket name and region)
    # If this fails: aws s3api delete-bucket --bucket $BUCKET_NAME --region ap-south-1
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region ap-south-1 --create-bucket-configuration LocationConstraint=ap-south-1

    # Allow public folders
    aws s3api put-public-access-block \
      --bucket "$BUCKET_NAME" \
      --public-access-block-configuration '{
        "BlockPublicAcls": false,
        "IgnorePublicAcls": false,
        "BlockPublicPolicy": false,
        "RestrictPublicBuckets": false
      }'

    # Make the bucket publicly readable (anyone can access the files)
    aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Sid\": \"PublicReadGetObject\",
        \"Effect\": \"Allow\",
        \"Principal\": \"*\",
        \"Action\": \"s3:GetObject\",
        \"Resource\": \"arn:aws:s3:::$BUCKET_NAME/*\"
      }]
    }"

    # Enable static hosting-style URLs if needed (optional, mostly for sites)
    aws s3 website "s3://$BUCKET_NAME/" --index-document index.html
    
    echo "Bucket $BUCKET_NAME created successfully with public permissions"
    exit 0
fi

# Handle file upload
if [[ -n "$BUCKET_PATH" && -n "$FILE_PATH" ]]; then
    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: file file not found: $FILE_PATH"
        exit 1
    fi
    
    # Construct the full S3 path including the destination filename
    S3_DESTINATION="$BUCKET_NAME/$BUCKET_PATH"
    
    # Upload the file to the specified path (including filename change)
    echo "Uploading $FILE_PATH to s3://$S3_DESTINATION"
    aws s3 cp "$FILE_PATH" "s3://$S3_DESTINATION"
    
    if [[ $? -eq 0 ]]; then
        echo "file uploaded successfully to s3://$S3_DESTINATION"
        echo "Public URL: https://$BUCKET_NAME.s3.ap-south-1.amazonaws.com/$BUCKET_PATH"
    else
        echo "Error: Failed to upload file"
        exit 1
    fi
else
    echo "Error: Both --path and --file are required for upload operations"
    echo "Usage:"
    echo "  $0 --bucket_name <name> --create"
    echo "  $0 --bucket_name <name> --path <path> --file <FILE_PATH>"
    exit 1
fi

