#!/usr/bin/env python3

# This script runs standalone and uploads a file to S3 as a user.
# Usage:
#       python hack/upload_as_user.py \
#           --app-name fomo \    (optional)
#           --app-type phone \    (optional)
#           --bucket-name fomomon \    (optional)
#           --path org1/file.jpg \    (required)
#           --file ./file.jpg \    (required)
#           --user user@example.com \    (required)
#           --password password \    (required)
#           --region ap-south-1 \    (optional)
#
# This will upload the file to the S3 bucket as the user.
import boto3
import click
import os

# Initialize AWS clients
cognito_idp = boto3.client('cognito-idp')
cognito_identity = boto3.client('cognito-identity')

# ------------------------------
# Helper: Idempotent find-or-create
# ------------------------------


def get_user_pool_id(app_name):
    """Get User Pool ID by name"""
    pools = cognito_idp.list_user_pools(MaxResults=60)['UserPools']
    for pool in pools:
        if pool['Name'] == f"{app_name}-user-pool":
            return pool['Id']
    raise ValueError(f"User Pool '{app_name}-user-pool' not found")


def get_user_pool_client_id(user_pool_id, app_name, app_type):
    """Get User Pool Client ID by name"""
    clients = cognito_idp.list_user_pool_clients(
        UserPoolId=user_pool_id, MaxResults=60)['UserPoolClients']
    for client in clients:
        if client['ClientName'] == f"{app_name}-{app_type}-client":
            return client['ClientId']
    raise ValueError(
        f"User Pool Client '{app_name}-{app_type}-client' not found")


def get_identity_pool_id(app_name, region):
    """Get Identity Pool ID by name"""
    pools = cognito_identity.list_identity_pools(MaxResults=60)[
        'IdentityPools']
    for pool in pools:
        if pool['IdentityPoolName'] == f"{app_name}-identity-pool":
            return pool['IdentityPoolId']
    raise ValueError(f"Identity Pool '{app_name}-identity-pool' not found")


def authenticate_user(email, password, client_id, region):
    """
    Authenticate user via Cognito User Pool to get ID token
    """
    client = boto3.client('cognito-idp', region_name=region)
    try:
        resp = client.initiate_auth(
            AuthFlow='USER_PASSWORD_AUTH',
            AuthParameters={
                'USERNAME': email,
                'PASSWORD': password
            },
            ClientId=client_id
        )

        if 'AuthenticationResult' in resp:
            id_token = resp['AuthenticationResult']['IdToken']
            return id_token
        else:
            # Handle challenge responses (like NEW_PASSWORD_REQUIRED)
            print(f"Authentication challenge: {resp}")
            raise ValueError(
                f"Authentication failed - challenge response: {resp.get('ChallengeName', 'Unknown')}")

    except client.exceptions.NotAuthorizedException:
        raise ValueError(f"Invalid username or password for user: {email}")
    except client.exceptions.UserNotFoundException:
        raise ValueError(f"User not found: {email}")
    except client.exceptions.UserNotConfirmedException:
        raise ValueError(f"User not confirmed: {email}")
    except Exception as e:
        raise ValueError(f"Authentication error: {str(e)}")


def get_aws_credentials(id_token, identity_pool_id, user_pool_id, region):
    """
    Exchange ID token for temporary AWS creds via Identity Pool
    """
    client = boto3.client('cognito-identity', region_name=region)
    # Step 1: Get identity ID
    identity = client.get_id(
        IdentityPoolId=identity_pool_id,
        Logins={f'cognito-idp.{region}.amazonaws.com/{user_pool_id}': id_token}
    )
    identity_id = identity['IdentityId']

    # Step 2: Get credentials for identity
    creds = client.get_credentials_for_identity(
        IdentityId=identity_id,
        Logins={f'cognito-idp.{region}.amazonaws.com/{user_pool_id}': id_token}
    )

    return creds['Credentials']


def upload_file_as_user(bucket_name, path, file_path, email, password, app_name, app_type, region):
    """
    Upload file to S3 using Cognito-authenticated user's credentials
    """
    # Get Cognito resource IDs
    user_pool_id = get_user_pool_id(app_name)
    client_id = get_user_pool_client_id(user_pool_id, app_name, app_type)
    identity_pool_id = get_identity_pool_id(app_name, region)

    # 1. Authenticate user to get ID token
    id_token = authenticate_user(email, password, client_id, region)

    # 2. Exchange ID token for AWS temp credentials
    creds = get_aws_credentials(
        id_token, identity_pool_id, user_pool_id, region)

    # 3. Create S3 client with temp creds
    s3 = boto3.client(
        's3',
        region_name=region,
        aws_access_key_id=creds['AccessKeyId'],
        aws_secret_access_key=creds['SecretKey'],
        aws_session_token=creds['SessionToken']
    )

    # 4. Upload file
    # Extract filename from file_path
    filename = os.path.basename(file_path)

    # Construct the full S3 key: path/filename
    # Remove trailing slash from path if present
    clean_path = path.rstrip('/')
    s3_key = f"{clean_path}/{filename}"

    s3.upload_file(file_path, bucket_name, s3_key)
    print(f"Uploaded {file_path} to s3://{bucket_name}/{s3_key} as {email}")


@click.command()
@click.option('--app-name', default='fomomon', help='Base name for Cognito resources')
@click.option('--app-type', default='phone', help='App type (phone, web, etc.)')
@click.option('--bucket-name', default='fomomon', help='S3 bucket name')
@click.option('--path', required=True, help='Path inside bucket (e.g., org1/file.jpg)')
@click.option('--file', required=True, help='Local file to upload')
@click.option('--user', required=True, help='User email (Cognito username)')
@click.option('--password', required=True, help='User password')
@click.option('--region', default='ap-south-1', help='AWS region')
def main(app_name, app_type, bucket_name, path, file, user, password, region):
    upload_file_as_user(bucket_name, path, file, user,
                        password, app_name, app_type, region)


if __name__ == "__main__":
    main()
