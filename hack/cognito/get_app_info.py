#!/usr/bin/env python3

import boto3
import click

# Initialize AWS clients
cognito_idp = boto3.client('cognito-idp')
cognito_identity = boto3.client('cognito-identity')
iam = boto3.client('iam')


def get_user_pool_id(app_name):
    """Get User Pool ID by name"""
    pools = cognito_idp.list_user_pools(MaxResults=60)['UserPools']
    for pool in pools:
        if pool['Name'] == f"{app_name}-user-pool":
            return pool['Id']
    return None


def get_user_pool_client_id(user_pool_id, app_name, app_type):
    """Get User Pool Client ID by name"""
    if not user_pool_id:
        return None
    clients = cognito_idp.list_user_pool_clients(
        UserPoolId=user_pool_id, MaxResults=60)['UserPoolClients']
    for client in clients:
        if client['ClientName'] == f"{app_name}-{app_type}-client":
            return client['ClientId']
    return None


def get_identity_pool_id(app_name):
    """Get Identity Pool ID by name"""
    pools = cognito_identity.list_identity_pools(MaxResults=60)[
        'IdentityPools']
    for pool in pools:
        if pool['IdentityPoolName'] == f"{app_name}-identity-pool":
            return pool['IdentityPoolId']
    return None


def get_role_arn(app_name, app_type):
    """Get Role ARN by name"""
    try:
        role_name = f"{app_name}-{app_type}-role"
        role = iam.get_role(RoleName=role_name)
        return role['Role']['Arn']
    except iam.exceptions.NoSuchEntityException:
        return None


@click.command()
@click.option('--app-name', default='fomomon', help='Base name for Cognito resources')
@click.option('--app-type', default='phone', help='App type (phone, web, etc.)')
def main(app_name, app_type):
    """Get Cognito resource IDs for the specified app"""

    print(f"Getting Cognito resources for {app_name}-{app_type}...")
    print("-" * 50)

    # Get User Pool ID
    user_pool_id = get_user_pool_id(app_name)
    if user_pool_id:
        print(f"User Pool ID: {user_pool_id}")
    else:
        print(f"User Pool '{app_name}-user-pool' not found")

    # Get Client ID
    client_id = get_user_pool_client_id(user_pool_id, app_name, app_type)
    if client_id:
        print(f"Client ID: {client_id}")
    else:
        print(f"Client '{app_name}-{app_type}-client' not found")

    # Get Identity Pool ID
    identity_pool_id = get_identity_pool_id(app_name)
    if identity_pool_id:
        print(f"Identity Pool ID: {identity_pool_id}")
    else:
        print(f"Identity Pool '{app_name}-identity-pool' not found")

    # Get Role ARN
    role_arn = get_role_arn(app_name, app_type)
    if role_arn:
        print(f"Role ARN: {role_arn}")
    else:
        print(f"Role '{app_name}-{app_type}-role' not found")


if __name__ == '__main__':
    main()
