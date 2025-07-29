#!/usr/bin/env python3

# This script runs standalone and adds users/orgs etc to the auth system.
# Usage:
#       python hack/add_users.py \
#           --app-name fomo \
#           --app-type phone \
#           --write true \
#           --user-config ./org1_users.json
#
# This will create 1 user and 1 identity pool, and one user pool client for the
# phone. It will then add all users listed in org1_users.json, and allow them
# IAM write/read access to the bucket_root in the org1_users.json file. See
# docs/auth.md for more details.

import json
import boto3
import click

# Initialize AWS clients
cognito_idp = boto3.client('cognito-idp')
cognito_identity = boto3.client('cognito-identity')
iam = boto3.client('iam')


def get_or_create_user_pool(name):
    pools = cognito_idp.list_user_pools(MaxResults=60)['UserPools']
    for pool in pools:
        if pool['Name'] == name:
            return pool['Id']
    resp = cognito_idp.create_user_pool(PoolName=name)
    return resp['UserPool']['Id']


def get_or_create_user_pool_client(pool_id, client_name):
    clients = cognito_idp.list_user_pool_clients(
        UserPoolId=pool_id, MaxResults=60)['UserPoolClients']
    for client in clients:
        if client['ClientName'] == client_name:
            # Update existing client to ensure proper auth flows
            try:
                cognito_idp.update_user_pool_client(
                    UserPoolId=pool_id,
                    ClientId=client['ClientId'],
                    ExplicitAuthFlows=[
                        'ALLOW_USER_PASSWORD_AUTH',
                        'ALLOW_REFRESH_TOKEN_AUTH'
                    ]
                )
                print(
                    f"Updated existing client {client['ClientId']} with USER_PASSWORD_AUTH flow")
            except Exception as e:
                print(f"Warning: Could not update client auth flows: {e}")
            return client['ClientId']
    resp = cognito_idp.create_user_pool_client(
        UserPoolId=pool_id,
        ClientName=client_name,
        GenerateSecret=False,
        ExplicitAuthFlows=[
            'ALLOW_USER_PASSWORD_AUTH',
            'ALLOW_REFRESH_TOKEN_AUTH'
        ]
    )
    return resp['UserPoolClient']['ClientId']


def get_or_create_identity_pool(name, user_pool_id, app_client_id, region):
    pools = cognito_identity.list_identity_pools(MaxResults=60)[
        'IdentityPools']
    for pool in pools:
        if pool['IdentityPoolName'] == name:
            return pool['IdentityPoolId']

    resp = cognito_identity.create_identity_pool(
        IdentityPoolName=name,
        AllowUnauthenticatedIdentities=False,
        CognitoIdentityProviders=[{
            'ProviderName': f'cognito-idp.{region}.amazonaws.com/{user_pool_id}',
            'ClientId': app_client_id
        }]
    )
    return resp['IdentityPoolId']


def get_or_create_role(role_name, bucket_root, write_access, identity_pool_id):
    # Check if role exists
    try:
        role = iam.get_role(RoleName=role_name)
        return role['Role']['Arn']
    except iam.exceptions.NoSuchEntityException:
        pass

    # Create role with trust policy
    trust_policy = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Federated": "cognito-identity.amazonaws.com"},
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "cognito-identity.amazonaws.com:aud": identity_pool_id
                },
                "ForAnyValue:StringLike": {
                    "cognito-identity.amazonaws.com:amr": "authenticated"
                }
            }
        }]
    }
    role = iam.create_role(
        RoleName=role_name,
        AssumeRolePolicyDocument=json.dumps(trust_policy)
    )

    # Build policy document
    actions = ["s3:GetObject"]
    if write_access:
        actions.append("s3:PutObject")

    # Convert bucket_root URL to proper S3 ARN format
    # bucket_root format: "https://fomomon.s3.amazonaws.com/t4gc/"
    print(f"Processing bucket_root: {bucket_root}")

    # Extract bucket name and path from URL
    if bucket_root.startswith("https://"):
        # Remove https:// and .s3.amazonaws.com/
        bucket_path = bucket_root.replace(
            "https://", "").replace(".s3.amazonaws.com", "")
        print(f"After removing https:// and .s3.amazonaws.com/: {bucket_path}")

        # Split into bucket name and path
        if "/" in bucket_path:
            bucket_name, path = bucket_path.split("/", 1)
            # Remove trailing slash from path
            path = path.rstrip("/")
            s3_resource = f"arn:aws:s3:::{bucket_name}/{path}/*"
            print(f"Bucket name: {bucket_name}, Path: {path}")
        else:
            s3_resource = f"arn:aws:s3:::{bucket_path}/*"
            print(f"Bucket name only: {bucket_path}")
    else:
        # Fallback if not a URL format
        s3_resource = f"arn:aws:s3:::{bucket_root}*"
        print(f"Using fallback format: {s3_resource}")

    print(f"Final S3 resource ARN: {s3_resource}")

    # Extract bucket name for more permissive policy
    bucket_name_only = s3_resource.split("/")[0].replace("arn:aws:s3:::", "")
    print(f"Bucket name only: {bucket_name_only}")

    policy_doc = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": actions,
            "Resource": [
                s3_resource,
                # Allow access to the exact path without wildcard
                s3_resource.replace("/*", ""),
                # Allow access to the path with trailing slash
                s3_resource.replace("/*", "/"),
                # Allow access to the entire bucket (for testing)
                # f"arn:aws:s3:::{bucket_name_only}/*"
            ]
        }]
    }

    print(f"Policy document: {json.dumps(policy_doc, indent=2)}")

    iam.put_role_policy(
        RoleName=role_name,
        PolicyName=f"{role_name}-policy",
        PolicyDocument=json.dumps(policy_doc)
    )

    return role['Role']['Arn']


def attach_role_to_identity_pool(identity_pool_id, role_arn):
    # Note: This overwrites previous mappings if not merged carefully.
    # In real-world, fetch current roles and update rather than overwrite.
    cognito_identity.set_identity_pool_roles(
        IdentityPoolId=identity_pool_id,
        Roles={"authenticated": role_arn}
    )


def add_users_to_pool(pool_id, users):
    for u in users:
        try:
            cognito_idp.admin_create_user(
                UserPoolId=pool_id,
                Username=u.get('user_id', u['email']).lower(),
                # This is a temp password, but we immediately set it to
                # permanent in the next step.
                TemporaryPassword=u['password'],
                # These are standard Cognito attributes: https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-attributes.html
                UserAttributes=[
                    {'Name': 'email', 'Value': u['email']},
                    {'Name': 'name', 'Value': u['name']},
                    {'Name': 'preferred_username', 'Value': u['user_id']}
                ],
                MessageAction='SUPPRESS'  # Don't send invitation email
            )

            # Set permanent password to avoid NEW_PASSWORD_REQUIRED challenge
            cognito_idp.admin_set_user_password(
                UserPoolId=pool_id,
                Username=u.get('user_id', u['email']).lower(),
                Password=u['password'],
                Permanent=True
            )
            print(f"Created user {u['email']} with permanent password")

        except cognito_idp.exceptions.UsernameExistsException:
            print(f"User {u['email']} already exists, skipping.")
            # Update existing user's password if needed
            try:
                cognito_idp.admin_set_user_password(
                    UserPoolId=pool_id,
                    Username=u.get('user_id', u['email']).lower(),
                    Password=u['password'],
                    Permanent=True
                )
                print(f"Updated password for existing user {u['email']}")
            except Exception as e:
                print(
                    f"Warning: Could not update password for {u['email']}: {e}")


@click.command()
@click.option('--app-name', default='fomomon', help='Base name for Cognito resources')
# TODO(prashanth@): add these as enums
@click.option('--app-type', default='phone', help='App type (phone, web, etc.)')
@click.option('--write', default='true', help='Write access (true/false)')
@click.option('--user-config', required=True, help='Path to user config JSON')
@click.option('--region', default='ap-south-1', help='AWS region')
def main(app_name, app_type, write, user_config, region):
    write_access = (write.lower() == 'true')

    # Load user config
    with open(user_config) as f:
        config = json.load(f)
    bucket_root = config['bucket_root']
    users = config['users']

    # 1. Create/find User Pool
    user_pool_id = get_or_create_user_pool(f"{app_name}-user-pool")

    # 2. Create/find User Pool Client for app_type
    client_id = get_or_create_user_pool_client(
        user_pool_id, f"{app_name}-{app_type}-client")

    # 3. Create/find Identity Pool
    identity_pool_id = get_or_create_identity_pool(
        f"{app_name}-identity-pool", user_pool_id, client_id, region)

    # 4. Create/find IAM Role scoped to bucket_root
    role_name = f"{app_name}-{app_type}-role"
    role_arn = get_or_create_role(
        role_name, bucket_root, write_access, identity_pool_id)

    # 5. Attach role to Identity Pool (authenticated role)
    attach_role_to_identity_pool(identity_pool_id, role_arn)

    # 6. Add users
    add_users_to_pool(user_pool_id, users)

    print(
        f"Setup complete:\nUser Pool ID: {user_pool_id}\nClient ID: {client_id}\nIdentity Pool ID: {identity_pool_id}\nRole ARN: {role_arn}")


if __name__ == '__main__':
    main()
