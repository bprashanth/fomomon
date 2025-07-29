#!/usr/bin/env python3

# This script deletes users and optionally all Cognito resources.
# Usage:
#   Delete all pools, clients, identity pools, roles
#       python hack/cognito/delete_users.py --all
#   Delete only users from config
#       python hack/cognito/delete_users.py --user-config ./org1_users.json
#       --app-name org1 --app-type phone --region ap-south-1

import json
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


def get_identity_pool_id(app_name, region):
    """Get Identity Pool ID by name"""
    pools = cognito_identity.list_identity_pools(MaxResults=60)[
        'IdentityPools']
    for pool in pools:
        if pool['IdentityPoolName'] == f"{app_name}-identity-pool":
            return pool['IdentityPoolId']
    return None


def delete_users_from_pool(pool_id, users):
    """Delete specific users from a User Pool"""
    if not pool_id:
        print("No User Pool found")
        return

    for u in users:
        username = u.get('user_id', u['email']).lower()
        try:
            cognito_idp.admin_delete_user(
                UserPoolId=pool_id,
                Username=username
            )
            print(f"Deleted user: {username}")
        except cognito_idp.exceptions.UserNotFoundException:
            print(f"User {username} not found, skipping")
        except Exception as e:
            print(f"Error deleting user {username}: {e}")


def delete_user_pool_clients(user_pool_id, app_name, app_type):
    """Delete User Pool Clients"""
    if not user_pool_id:
        return

    clients = cognito_idp.list_user_pool_clients(
        UserPoolId=user_pool_id, MaxResults=60)['UserPoolClients']

    for client in clients:
        if client['ClientName'] == f"{app_name}-{app_type}-client":
            try:
                cognito_idp.delete_user_pool_client(
                    UserPoolId=user_pool_id,
                    ClientId=client['ClientId']
                )
                print(f"Deleted User Pool Client: {client['ClientName']}")
            except Exception as e:
                print(f"Error deleting client {client['ClientName']}: {e}")


def delete_identity_pool(app_name, region):
    """Delete Identity Pool"""
    identity_pool_id = get_identity_pool_id(app_name, region)
    if not identity_pool_id:
        print(f"Identity Pool '{app_name}-identity-pool' not found")
        return

    try:
        cognito_identity.delete_identity_pool(IdentityPoolId=identity_pool_id)
        print(f"Deleted Identity Pool: {app_name}-identity-pool")
    except Exception as e:
        print(f"Error deleting identity pool: {e}")


def delete_iam_role(app_name, app_type):
    """Delete IAM Role and its policies"""
    role_name = f"{app_name}-{app_type}-role"

    try:
        # List and delete inline policies
        policies = iam.list_role_policies(RoleName=role_name)['PolicyNames']
        for policy_name in policies:
            try:
                iam.delete_role_policy(
                    RoleName=role_name, PolicyName=policy_name)
                print(f"Deleted inline policy: {policy_name}")
            except Exception as e:
                print(f"Error deleting inline policy {policy_name}: {e}")

        # List and detach managed policies
        attached_policies = iam.list_attached_role_policies(RoleName=role_name)[
            'AttachedPolicies']
        for policy in attached_policies:
            try:
                iam.detach_role_policy(
                    RoleName=role_name, PolicyArn=policy['PolicyArn'])
                print(f"Detached managed policy: {policy['PolicyName']}")
            except Exception as e:
                print(
                    f"Error detaching managed policy {policy['PolicyName']}: {e}")

        # Delete the role
        iam.delete_role(RoleName=role_name)
        print(f"Deleted IAM Role: {role_name}")

    except iam.exceptions.NoSuchEntityException:
        print(f"IAM Role {role_name} not found")
    except Exception as e:
        print(f"Error deleting IAM role {role_name}: {e}")


def delete_user_pool(app_name):
    """Delete User Pool and all its contents"""
    user_pool_id = get_user_pool_id(app_name)
    if not user_pool_id:
        print(f"User Pool '{app_name}-user-pool' not found")
        return

    try:
        cognito_idp.delete_user_pool(UserPoolId=user_pool_id)
        print(f"Deleted User Pool: {app_name}-user-pool")
    except Exception as e:
        print(f"Error deleting user pool: {e}")


def delete_all_resources(app_name, app_type, region):
    """Delete all Cognito resources for the app"""
    print(f"Deleting all resources for {app_name}-{app_type}...")

    # Delete in reverse order of dependencies
    # 1. Delete Identity Pool first (depends on User Pool Client)
    delete_identity_pool(app_name, region)

    # 2. Delete IAM Role
    delete_iam_role(app_name, app_type)

    # 3. Delete User Pool (this will delete all clients and users)
    delete_user_pool(app_name)

    print("All resources deleted successfully!")


@click.command()
@click.option('--app-name', default='fomomon', help='Base name for Cognito resources')
@click.option('--app-type', default='phone', help='App type (phone, web, etc.)')
@click.option('--user-config', help='Path to user config JSON (for deleting specific users)')
@click.option('--all', is_flag=True, help='Delete all Cognito resources (pools, clients, identity pools, roles)')
@click.option('--region', default='ap-south-1', help='AWS region')
def main(app_name, app_type, user_config, all, region):
    """Delete Cognito users and optionally all resources"""

    if not all and not user_config:
        print("Error: Must specify either --all or --user-config")
        return

    if all:
        delete_all_resources(app_name, app_type, region)

    if user_config:
        # Load user config
        with open(user_config) as f:
            config = json.load(f)
        users = config['users']

        if all:
            print("Note: Users were already deleted with --all flag")
        else:
            # Delete only specific users, preserve pools
            user_pool_id = get_user_pool_id(app_name)
            if user_pool_id:
                print(f"Deleting users from {app_name}-user-pool...")
                delete_users_from_pool(user_pool_id, users)
            else:
                print(f"User Pool '{app_name}-user-pool' not found")


if __name__ == '__main__':
    main()
