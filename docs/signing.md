# AWS request signing 

The API for signing is the "canonical request", which is formatted as follows 
```console 
// This is what we're building in the s3_signer_service:
[
  method,           // "PUT"
  uri,              // "/t4gc/left_6th/file.jpg"
  queryString,      // "X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=..."
  headers,          // "host:bucket.s3.region.amazonaws.com\ncontent-type:image/jpeg\n"
  signedHeaders,    // "host;content-type"
  payloadHash       // "UNSIGNED-PAYLOAD"
].join('\n')
```
This request is used in the calculation of the signature, which happens as follows 
1. Hash the canonical reuqest 
2. Create the final string to sign, that includes the hash
3. Sign this using the "secret key" 
4. Add the signature to the url 

So the final url is: baseURL + query params + `x-Amz-Signature=signature`

## Exammple 

Starting with `https://fomomon.s3.ap-south-1.amazonaws.com/t4gc/file.jpg`
We need to add a few query params
```
https://fomomon.s3.ap-south-1.amazonaws.com/t4gc/file.jpg?
X-Amz-Algorithm=AWS4-HMAC-SHA256&
X-Amz-Credential=AS<somekey>/20250730/ap-south-1/s3/aws4_request&
X-Amz-Date=20250730T150000Z&
X-Amz-Expires=900&
X-Amz-SignedHeaders=host&
X-Amz-Security-Token=IQoJb3JpZ2luX2VjEJf...
```
Turn this into the canonical request, hash it and sign it using the "secret key" - then add the signature back to the url
```
https://fomomon.s3.ap-south-1.amazonaws.com/t4gc/file.jpg?
X-Amz-Algorithm=AWS4-HMAC-SHA256&
X-Amz-Credential=AS<somekey>/20250730/ap-south-1/s3/aws4_request&
X-Amz-Date=20250730T150000Z&
X-Amz-Expires=900&
X-Amz-SignedHeaders=host&
X-Amz-Security-Token=IQoJb3JpZ2luX2VjEJf...&
X-Amz-Signature=a1b2c3d4e5f6...
```

## Obtaining the "Secret key" 

The secret key is made up of 3 elements: 
1. Access key ID: this is an id aws can use to look up a secret key 
2. The actual secret key (`secret access key`): the key used to sign 
3. Session token: identifies the logged in user 

These are retrieved from the Auth service as follows 
1. `authService.login(email, password)`: generates the session token
2. `authService.getUploadCredentials()`: exchanges sessions token for access key id
3. Not authService, but `s3SignerService.createPresignedPutUrl`: uses these creds to sign the url as shown above

```
Client                    AWS Cognito Identity Pool
  |                              |
  |-- ID Token ----------------->|
  |                              |
  |<-- Access Key ID ------------|
  |<-- Secret Access Key --------|
  |<-- Session Token ------------|
  |                              |
  |                              |
  |-- Signed Request ----------->| AWS S3
  |   (includes Access Key ID)   |
  |   (includes Signature)       |
```
In more detail and end to end 
```
┌─────────────┐                    ┌─────────────────────┐                    ┌─────────────────────┐
│             │                    │  Cognito User Pool  │                    │ Cognito Identity    │
│   Client    │                    │  (User Management)  │                    │ Pool (AWS Creds)    │
│             │                    │                     │                    │                     │
└─────┬───────┘                    └─────────┬───────────┘                    └─────────┬───────────┘
      │                                      │                                        │
      │ 1. Login Request                     │                                        │
      │    username: "user@example.com"      │                                        │
      │    password: "password123"           │                                        │
      │─────────────────────────────────────>│                                        │
      │                                      │                                        │
      │                                      │ 2. Authenticate User                   │
      │                                      │    - Verify credentials                │
      │                                      │    - Generate JWT tokens               │
      │                                      │                                        │
      │ 3. Login Response                    │                                        │
      │    - ID Token (JWT): user info       │                                        │
      │    - Access Token (JWT): API perms   │                                        │
      |       (this is unused)               |                                        |
      │    - Refresh Token                   │                                        │
      │<─────────────────────────────────────│                                        │
      │                                      │                                        │
      │ 4. Get AWS Credentials Request       │                                        │
      │    - ID Token (JWT)                  │                                        │
      │    - Identity Pool ID                │                                        │
      │─────────────────────-────────────────────────────────────────────────────────>│
      │                                      │                                        │
      │                                      │                                        │ 5. Exchange ID Token
      │                                      │                                        │    - Validate JWT
      │                                      │                                        │    - Check IAM role
      │                                      │                                        │    - Generate temp creds
      │                                      │                                        │
      │ 6. AWS Credentials Response          │                                        │
      │    - Access Key ID: ASIAQLSIVNNS...  │                                        │
      │    - Secret Access Key: [40 chars]   │                                        │
      │    - Session Token: [1304 chars]     │                                        │
      │    - Expiration: 1 hour              │                                        │
      │<───────────────────-──────────────────────────────────────────────────────────│
      │                                      │                                        │
      │ 7. Create Presigned URL              │                                        │
      │    - Use temp credentials            │                                        │
      │    - Sign request with Secret Key    │                                        │
      │    - Generate presigned URL          │                                        │
      │                                      │                                        │
      │ 8. Upload to S3                      │                                        │
      │    - PUT to presigned URL            │                                        │
      │    - Include file data               │                                        │
      │───────────────────-──────────────────────────────────────────────────────────>│
```
## Appendix 

Reference docs 
* AWS docs on [signature v4](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html)
* S3 Presigned [urls docs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html)
* Cognito id pool [docs](https://docs.aws.amazon.com/cognito/latest/developerguide/authentication.html)

