# Authentication/Authorization 

Adding new users, apps and orgs are all one command  
```
$ source venv/bin/activate 
$ python hack/cognito/add_users.py \
  --app-name fomo \
  --app-type phone \
  --write true \
  --user-config ./org1_users.json
```
Testing this as one of the users in org1 (check config/users/ for actual passwords, these files are not checked-in)
```
$ python3 ./hack/cognito/upload_as_user.py --file ~/Downloads/testsheet.xlsx --path t4gc/ --user foo --password barissometext
```
Retrieving app info
```
$ python3 hack/cognito/get_app_info.py
$ python3 hack/cognito/get_app_info.py --app-name fomo --app-type web
```
You can then use the following to get a list of users 
```
$  aws cognito-idp list-users --user-pool-id <id from above command>
```
Deleting all users 
```
$ python3 ./hack/cognito/delete_users.py  --all
```
This will
1. Revoke all active sessions/tokens
2. Refresh tokens stop working 
3. Password history is lost (re-use of passwords is allowed) 

But users will be able to re-login right after you re-run the `add_users` script. 

## Overview 

AWS Cognito has 2 components for access

1. User Pool for authN - these are tokens exchanged for username/password 
	- This is where all users are stored
	- These users can access the same resources across different apps 
2. Identity Pool for authZ 
	- these are IAM roles exchanged for tokens + `client_id`
	- different IAM roles are added for diffrent `client_id`
	- `client_id` hardcoded in apps 
3. User pool client 
	- Per app config for eg token validity, allowing oauth, redirects etc 
	- The identity pool can map different IAMs based on the incoming user pool config

Both these are bound to a region, eg `ap-south-1`. 

## Users 

Users are added via the `users.json`
```
{
  "bucket_root": "https://fomomon.s3.amazonaws.com/t4gc/",
  "users": [
    {
      "user_id": "prashanthb",
      "name": "Prashanth B",
      "email": "prashanth@tech4goodcommunity.com"
    },
    {
      "user_id": "lakshmi_n",
      "name": "Lakshmi Narayan",
      "email": "lakshmi@ngo.org"
    }
  ]
}

```

## Scoping permissions per org

The `bucket_root` from `users.json` is included in the IAM policy attached to the identity pool.



# Auth service 

Pseudo code 
```
class AuthService {
  AuthService._privateConstructor();
  static final AuthService instance = AuthService._privateConstructor();

  String? _idToken;
  String? _refreshToken;
  DateTime? _expiryTime;

  Future<void> login(String email, String password) async {
    // Authenticate with Cognito User Pool
    // Store idToken, refreshToken, expiryTime
  }

  Future<String?> getValidIdToken() async {
    if (_idToken == null || DateTime.now().isAfter(_expiryTime!)) {
      await _refreshTokens();
    }
    return _idToken;
  }

  Future<void> _refreshTokens() async {
    // Use refreshToken to get new idToken
    // If refreshToken expired, force re-login
  }
}
```


## Appendix 

### Auditing access 


To check whether a app/bucket has public write access
```
$ hack/s3/check_public_access.sh <app name> (eg fomomon)
```

### Updating auth policies 

Because the script that creates auth pools just checks that the pool exists, it might be difficult to update auth policies on the pool idempotently. If the need arises, you can follow the pattern used to update the user pool client, i.e 
```python 
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
```
