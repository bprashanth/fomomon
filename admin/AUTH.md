# Current state                                                                               
                                                                                              
Two principals, two buckets in play:                                                      

```
Principal: Flutter app (authenticated via Identity Pool)
Role: fomomon-phone-role                                                                    
Current S3 permissions: GetObject, PutObject, ListBucket on fomomon/
The phone and admin panels are the only writers 
────────────────────────────────────────                                                    
Principal: Lambda server                                                                    
Role: form-idable-lambda-role
Current S3 permissions: GetObject, ListBucket on fomomon + fomomonguest + forestfomo-images
  — missing PutObject, because the lambda server currently only reads from the bucket 
```
  
## Issues

Permissions are managed in many places 

* The bucket policy lives in AWS (no file in any repo)
* The phone role policy lives in AWS (no file in any repo)
* and the lambda policy lives in lambda-policy.json but only gets applied when you run setup.sh (see good-shepherd/server).

However this is not a massive issue since this admin panel is capable of syncing permissions. The `Sync auth_config.json` button enforces permissions: 
- Removes public read access from the bucket (except `auth_config.json`).
- Ensures the Cognito identity pool role can read, write, and list the bucket.

## Notes on permissions

The admin API uses server-side AWS credentials only. There is no end-user login in the UI today. If the S3 bucket is made private, the admin server continues to work as long as the AWS principal used to run it has the required permissions. 

However, clients must use the cognito tokens + presigned urls to get/put, OR auth with the lambda server and then invoke an api. The lambda server is allowed access to the bucket regardless of any `auth_config.json` enforcement - meaning the enforcement this admin ui performs is only for clients configured via the pools mentioned in `auth_config.json`. 

### authconfig.json behavior

The admin server treats the bucket’s `auth_config.json` as the source of truth.
- If `auth_config.json` exists, the sync action will not overwrite it.
- If it does not exist, the UI will show setup instructions (create the Cognito resources and upload `auth_config.json`).

