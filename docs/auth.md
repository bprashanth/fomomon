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
See [docs/signing](signing.md) for a better flow diagram of how this works. 

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

## Validity and Scope 

The `bucket_root` from `users.json` is included in the IAM policy attached to the identity pool.

## On the validity of URLs 

There are 2 options, and we take the former currently
1. Allow puublic GET on the bucket and include the direct url to the object 
2. Somehow keep re-signing urls once in seven days 
	- Write a lambda service 
	- Maintain a api server 


# Auth service 

The question of libraries in the auth service is pertinent
1. Using Amplify which is an official AWS library, ties us closer to AWS. It also requires heavier setup (cli based init etc). If we assume we will _always_ use s3 for object store and cognito for auth, we are not tied too heavily to aws - so maybe this is a good argument for it. 
2. The use of community maintained libraries lets us swap out one of these, or just get off the ground without too much cli initialization. 

For now, we have chosen 2, mostly because it allows manual configuration of User Pool, App Client, identity pool, s3 buckets. Here is the flow of control
```
1. Get temporary AWS credentials
2. Create signed headers with AWS Signature V4
3. Upload file with signed headers 
4. Return normal S3 URL 
```

### How does the phone app figure out the cognito pools 

Basically the phone app needs to do the equivalent of `aws cognito-idp-list-users` for which it needs a `user-pool-id`. There are 2 ways we can transfer this user pool id

1. Embed it in the app. This means if the user pool changes, the app needs an update.
2. Embed it in a `auth_config.json` that's stored in the backend with public-read, and embed that path in the app. 

Since getting this auth config will be one of the first things the app does, it must be public and small. It must also never contain secret pii information that eg leaks user credentials. 

## Pseudo code 

This is the skeleton auth service 

```
class AuthService {
  String? _idToken;
  String? _refreshToken;
  DateTime? _expiryTime;

  Future<void> login(String email, String password) async {
    // Authenticate with Cognito User Pool
    // Store idToken, refreshToken, expiryTime
  }

  // This returns the "user" token
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

  Future<Map<String, dynamic>> getUploadCredentials() async {
    // Generate identity credentials using the user credentials
    // These identity creds are used to sign the upload url. 
  }
}
```
For more details on url signing, see [docs/signing.md](signing.md)

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
