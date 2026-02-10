import json
from dataclasses import dataclass
from typing import List, Dict, Optional

import boto3


@dataclass
class CognitoAppInfo:
    user_pool_id: str
    client_id: str
    identity_pool_id: str
    role_arn: str


class CognitoService:
    def __init__(self, app_name: str, app_type: str, region: str, bucket_name: str):
        self.app_name = app_name
        self.app_type = app_type
        self.region = region
        self.bucket_name = bucket_name
        self.cognito_idp = boto3.client("cognito-idp", region_name=region)
        self.cognito_identity = boto3.client("cognito-identity", region_name=region)
        self.iam = boto3.client("iam", region_name=region)

    def get_or_create_user_pool(self) -> str:
        pools = self.cognito_idp.list_user_pools(MaxResults=60)["UserPools"]
        for pool in pools:
            if pool["Name"] == f"{self.app_name}-user-pool":
                return pool["Id"]
        resp = self.cognito_idp.create_user_pool(PoolName=f"{self.app_name}-user-pool")
        return resp["UserPool"]["Id"]

    def get_or_create_user_pool_client(self, pool_id: str) -> str:
        clients = self.cognito_idp.list_user_pool_clients(UserPoolId=pool_id, MaxResults=60)[
            "UserPoolClients"
        ]
        for client in clients:
            if client["ClientName"] == f"{self.app_name}-{self.app_type}-client":
                try:
                    self.cognito_idp.update_user_pool_client(
                        UserPoolId=pool_id,
                        ClientId=client["ClientId"],
                        ExplicitAuthFlows=[
                            "ALLOW_USER_PASSWORD_AUTH",
                            "ALLOW_USER_SRP_AUTH",
                            "ALLOW_REFRESH_TOKEN_AUTH",
                        ],
                    )
                except Exception:
                    pass
                return client["ClientId"]
        resp = self.cognito_idp.create_user_pool_client(
            UserPoolId=pool_id,
            ClientName=f"{self.app_name}-{self.app_type}-client",
            GenerateSecret=False,
            ExplicitAuthFlows=[
                "ALLOW_USER_PASSWORD_AUTH",
                "ALLOW_USER_SRP_AUTH",
                "ALLOW_REFRESH_TOKEN_AUTH",
            ],
        )
        return resp["UserPoolClient"]["ClientId"]

    def get_or_create_identity_pool(self, user_pool_id: str, client_id: str) -> str:
        pools = self.cognito_identity.list_identity_pools(MaxResults=60)["IdentityPools"]
        for pool in pools:
            if pool["IdentityPoolName"] == f"{self.app_name}-identity-pool":
                return pool["IdentityPoolId"]

        resp = self.cognito_identity.create_identity_pool(
            IdentityPoolName=f"{self.app_name}-identity-pool",
            AllowUnauthenticatedIdentities=False,
            CognitoIdentityProviders=[
                {
                    "ProviderName": f"cognito-idp.{self.region}.amazonaws.com/{user_pool_id}",
                    "ClientId": client_id,
                }
            ],
        )
        return resp["IdentityPoolId"]

    def get_or_create_role(self, identity_pool_id: str, write_access: bool) -> str:
        role_name = f"{self.app_name}-{self.app_type}-role"
        try:
            role = self.iam.get_role(RoleName=role_name)
            role_exists = True
        except self.iam.exceptions.NoSuchEntityException:
            role_exists = False

        if not role_exists:
            trust_policy = {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {"Federated": "cognito-identity.amazonaws.com"},
                        "Action": "sts:AssumeRoleWithWebIdentity",
                        "Condition": {
                            "StringEquals": {
                                "cognito-identity.amazonaws.com:aud": identity_pool_id
                            },
                            "ForAnyValue:StringLike": {
                                "cognito-identity.amazonaws.com:amr": "authenticated"
                            },
                        },
                    }
                ],
            }
            role = self.iam.create_role(
                RoleName=role_name,
                AssumeRolePolicyDocument=json.dumps(trust_policy),
            )
        else:
            role = role

        actions = ["s3:GetObject"]
        if write_access:
            actions.append("s3:PutObject")

        s3_resources = [
            f"arn:aws:s3:::{self.bucket_name}/*",
            f"arn:aws:s3:::{self.bucket_name}",
            f"arn:aws:s3:::{self.bucket_name}/",
        ]

        policy_doc = {
            "Version": "2012-10-17",
            "Statement": [{"Effect": "Allow", "Action": actions, "Resource": s3_resources}],
        }

        self.iam.put_role_policy(
            RoleName=role_name,
            PolicyName=f"{role_name}-policy",
            PolicyDocument=json.dumps(policy_doc),
        )

        return role["Role"]["Arn"]

    def attach_role_to_identity_pool(self, identity_pool_id: str, role_arn: str) -> None:
        self.cognito_identity.set_identity_pool_roles(
            IdentityPoolId=identity_pool_id, Roles={"authenticated": role_arn}
        )

    def ensure_app_setup(self, write_access: bool = True) -> CognitoAppInfo:
        user_pool_id = self.get_or_create_user_pool()
        client_id = self.get_or_create_user_pool_client(user_pool_id)
        identity_pool_id = self.get_or_create_identity_pool(user_pool_id, client_id)
        role_arn = self.get_or_create_role(identity_pool_id, write_access)
        self.attach_role_to_identity_pool(identity_pool_id, role_arn)
        return CognitoAppInfo(
            user_pool_id=user_pool_id,
            client_id=client_id,
            identity_pool_id=identity_pool_id,
            role_arn=role_arn,
        )

    def list_users(self, user_pool_id: str) -> List[Dict[str, str]]:
        users: List[Dict[str, str]] = []
        paginator = self.cognito_idp.get_paginator("list_users")
        for page in paginator.paginate(UserPoolId=user_pool_id):
            for user in page.get("Users", []):
                attrs = {a["Name"]: a["Value"] for a in user.get("Attributes", [])}
                users.append(
                    {
                        "username": user.get("Username"),
                        "email": attrs.get("email"),
                        "name": attrs.get("name"),
                        "preferred_username": attrs.get("preferred_username"),
                        "status": user.get("UserStatus"),
                        "enabled": user.get("Enabled"),
                    }
                )
        return users

    def add_user(
        self,
        user_pool_id: str,
        username: str,
        name: str,
        email: str,
        password: str,
    ) -> None:
        username = username.lower()
        self.cognito_idp.admin_create_user(
            UserPoolId=user_pool_id,
            Username=username,
            TemporaryPassword=password,
            UserAttributes=[
                {"Name": "email", "Value": email},
                {"Name": "name", "Value": name},
                {"Name": "preferred_username", "Value": username},
            ],
            MessageAction="SUPPRESS",
        )
        self.cognito_idp.admin_set_user_password(
            UserPoolId=user_pool_id,
            Username=username,
            Password=password,
            Permanent=True,
        )

    def delete_user(self, user_pool_id: str, username: str) -> None:
        self.cognito_idp.admin_delete_user(
            UserPoolId=user_pool_id,
            Username=username.lower(),
        )

    def update_password(self, user_pool_id: str, username: str, password: str) -> None:
        self.cognito_idp.admin_set_user_password(
            UserPoolId=user_pool_id,
            Username=username.lower(),
            Password=password,
            Permanent=True,
        )

    def get_app_info(self) -> Optional[CognitoAppInfo]:
        user_pool_id = None
        pools = self.cognito_idp.list_user_pools(MaxResults=60)["UserPools"]
        for pool in pools:
            if pool["Name"] == f"{self.app_name}-user-pool":
                user_pool_id = pool["Id"]
                break

        if not user_pool_id:
            return None

        client_id = None
        clients = self.cognito_idp.list_user_pool_clients(
            UserPoolId=user_pool_id, MaxResults=60
        )["UserPoolClients"]
        for client in clients:
            if client["ClientName"] == f"{self.app_name}-{self.app_type}-client":
                client_id = client["ClientId"]
                break

        identity_pool_id = None
        pools = self.cognito_identity.list_identity_pools(MaxResults=60)["IdentityPools"]
        for pool in pools:
            if pool["IdentityPoolName"] == f"{self.app_name}-identity-pool":
                identity_pool_id = pool["IdentityPoolId"]
                break

        role_name = f"{self.app_name}-{self.app_type}-role"
        try:
            role = self.iam.get_role(RoleName=role_name)
            role_arn = role["Role"]["Arn"]
        except self.iam.exceptions.NoSuchEntityException:
            role_arn = ""

        return CognitoAppInfo(
            user_pool_id=user_pool_id,
            client_id=client_id or "",
            identity_pool_id=identity_pool_id or "",
            role_arn=role_arn,
        )

    def get_password_policy(self, user_pool_id: str) -> Dict[str, object]:
        resp = self.cognito_idp.describe_user_pool(UserPoolId=user_pool_id)
        policies = resp.get("UserPool", {}).get("Policies", {})
        return policies.get("PasswordPolicy", {})
