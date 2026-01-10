# Fomomon V2: system redesign

This document outlines the redesign of the Fomomon application, focusing on improving the architecture, user experience, and overall functionality.

## Table of Contents

0.  [Introduction](#introduction)
1.  [Authentication](#deep-dive-on-authentication)
2.  [Configuration Download](#deep-dive-on-configuration-download)
3.  [Image Download](#deep-dive-on-image-download)
4.  [Data Upload](#deep-dive-on-data-upload)
5.  [Do we need an API server?](#do-we-need-an-API-server)

## Introduction 

### Authentication

The current authentication flow is a direct-to-AWS serverless model.

1.  **Config Fetch**: The app fetches a public `auth_config.json` file from S3 to get Cognito pool details.

2.  **Authentication**: The app uses the `amazon_cognito_identity_dart_2` library to directly authenticate with Cognito User Pools.

3.  **Authorization**: It exchanges the Cognito ID token for temporary AWS IAM credentials through a Cognito Identity Pool.

4.  **Direct Access**: The app uses these credentials to directly access other AWS services like S3.

### Configuration Download

There are 2 pieces of configuration downloaded. The first is the `auth_config.json` mentioned in the previous section. The second is a per org `sites.json`.

The current flow for downloading `sites.json` is:

1.  **Direct S3 Access**: The app constructs a URL and makes a direct, unauthenticated HTTP GET request to `sites.json` in the organization's S3 bucket.

2.  **Public Access Required**: This requires the `sites.json` file for every organization to be publicly readable.

3.  **Client-Side Caching**: The downloaded file is cached on the device for offline use.

### Image Download

The flow for downloading reference "ghost" images is similar:

1.  **Direct S3 Access**: After parsing `sites.json`, the app constructs URLs for each reference image and downloads them directly via unauthenticated HTTP GET requests.

2.  **Public Access Required**: This requires all reference images to be publicly readable in S3.

3.  **Client-Side Caching**: Images are cached locally in a `ghosts` directory for offline use.

### Data Upload

The current data upload flow relies on pre-signed S3 URLs:

1.  **Get Credentials**: The app gets temporary AWS credentials from Cognito.
2.  **Generate Pre-signed URL**: It uses a service to create a pre-signed S3 PUT URL for each file to be uploaded (images and session JSON). This is a time-limited, authenticated URL for a specific S3 object.
3.  **Direct S3 Upload**: The app performs an HTTP `PUT` request directly to the pre-signed URL to upload the file.
4.  **Sequential & Non-Transactional**: This process is handled sequentially on the client (image 1, then image 2, then JSON). If a step fails, it can result in orphaned files in S3.

## Deep dive on Authentication 

The system uses a combination of AWS Cognito and IAM to manage user authentication and control access to S3 buckets. The setup is automated by the `hack/cognito/add_users.py` script.

Here are the core components:

* Cognito User Pool: A single user pool, named {app-name}-user-pool (e.g., fomo-user-pool), acts as the central user directory for authentication (AuthN). All users from all organizations
are created within this pool.
* Cognito Identity Pool: An identity pool, named {app-name}-identity-pool (e.g., fomo-identity-pool), is used for authorization (AuthZ). It exchanges the authentication token from the
User Pool for temporary AWS credentials.
* IAM Role: The script creates an IAM role named {app-name}-{app-type}-role (e.g., fomo-phone-role). This role has a policy attached to it that grants permissions to a specific S3 bucket
path. When a user authenticates, they assume this role.
* User Config JSON: These files (like `config/users/t4gc_users.json.template`) are the source of truth for creating users and setting permissions. Each file defines an organization's users
and, critically, the `bucket_root` which points to that organization's data in S3.

The Flow: From User Login to S3 Access

1. Authentication: A user logs into the mobile app. The app sends the credentials to the Cognito User Pool.
2. Token Exchange: If successful, the User Pool returns an ID token to the app.
3. Authorization: The app then presents this ID token to the Cognito Identity Pool.
4. Assume Role: The Identity Pool, which is configured to trust the User Pool, validates the token and grants the user temporary AWS credentials by allowing them to assume the associated
IAM Role (fomo-phone-role).
5. S3 Access: The app uses these temporary credentials to access S3. The permissions (read/write access to a specific S3 bucket path) are determined by the policy attached to the IAM
Role.

### Adding a New Organization

To add a new organization, you would perform the following actions:

1. Prepare S3: Create a new "folder" (S3 prefix) for the organization within your main S3 bucket (e.g., s3://fomomon-data/new-org/).
2. Create User Config: Create a new user configuration JSON file (e.g., `config/users/new-org_users.json`). In this file, you must:
* Set the `bucket_root` to the S3 path of the new organization (e.g., "https://fomomon-data.s3.amazonaws.com/new-org/").
* Add the list of users for this new organization, including their `user_id`, name, email, and a temporary password.
3. Run the Script: Execute the `add_users.py` script, pointing to your new configuration file.

```
     python hack/cognito/add_users.py \
       --app-name fomo \
       --app-type phone \
       --write true \
       --user-config config/users/new-org_users.json
```

This command will reuse the existing Cognito User Pool and Identity Pool but will overwrite the policy of the existing IAM Role (fomo-phone-role) to grant access to the new
organization's `bucket_root`.

Important Caveat: Due to the fact that the IAM Role name is static (fomo-phone-role), this script does not properly support multiple organizations simultaneously under the same
app-name. When you add a new organization, the previous one will lose S3 access because the role's policy is updated to point to the new bucket.

### Adding a New User

To add a new user to an existing organization:

1. Update User Config: Add the new user's details to the organization's existing user JSON file.
2. Re-run the Script: Run the `add_users.py` script again, pointing to the same configuration file.

The script will see that the Cognito pools and IAM role already exist. It will then iterate through the user list, find the new user, and create them in the User Pool. Existing users
are skipped. Since the new user is part of the same User Pool, they automatically inherit the ability to assume the IAM role and gain access to the organization's S3 bucket.

### Code workflow 

Current Authentication Flow:

1. Configuration Fetch:
* The LoginScreen initiates an asynchronous call to `AuthService.fetchAuthConfig()`.
* This method constructs a URL to an `auth_config.json` file stored directly in an S3 bucket (e.g.,
 `https://fomomon.s3.ap-south-1.amazonaws.com/auth_config.json`).
* It fetches and parses this file to get critical Cognito details: `userPoolId`, `clientId`, and `identityPoolId`.
* This `auth_config.json` file must be publicly readable on S3, as this call is unauthenticated.

2. User Authentication:
* When the user submits their credentials (name and password), the `_handleSubmit` method calls `AuthService.login()`.
* The `AuthService` uses the `amazon_cognito_identity_dart_2` package to directly communicate with the AWS Cognito User Pool.
* It authenticates the user and, if successful, receives an ID token, refresh token, and session details from Cognito.

3. Authorization & AWS Credentials:
* For subsequent operations requiring AWS access (like uploading a file), the app calls `AuthService.getUploadCredentials()`.
* This method first ensures it has a valid ID token (refreshing it if necessary).
* It then uses the `CognitoCredentials` provider from the same library to exchange the user's valid ID token for temporary AWS IAM
 credentials (access key, secret key, session token) via the Cognito Identity Pool.

4. Direct AWS Service Interaction:
* Armed with these temporary credentials, the application can now directly sign and make requests to other AWS services, such as
 putting an object in an S3 bucket. The permissions for these actions are governed by the IAM Role associated with the authenticated
 user in the Identity Pool.

## Deep dive: configuration download

1. Initiation: The process starts in the `SitePrefetchScreen`, which calls
`SiteService.fetchSitesAndPrefetchImages()`. This screen is shown after a successful login
to ensure all necessary data is available offline.

2. `sites.json` Fetching:
* The SiteService constructs a URL to the sites.json file located in the organization's
 S3 bucket (e.g., `https://fomomon-data.s3.amazonaws.com/t4gc/sites.json`).
* It uses the http package to make a direct, unauthenticated GET request to download
 this JSON file. This implies that the sites.json file for each organization must be
 publicly readable.
* The downloaded JSON is then cached locally on the device in the application's
 documents directory (`.../cache/sites.json`).

3. Ghost Image Fetching (Prefetching):
* After parsing sites.json, the service iterates through the list of sites.
* For each site, it constructs the full URL for the `reference_portrait` and
 `reference_landscape` images using the `bucket_root` and the image paths from the site
 data.
* It calls `_ensureCachedImage`, which checks if the image already exists in the local
 cache (`.../ghosts/<siteId>/<imageName>`).
* If the image is not found locally, it is downloaded via a direct, unauthenticated
 HTTP GET request and saved to the cache. Again, this requires the reference images in
 S3 to be publicly readable.

4. Caching and Offline First:
* The SiteService is designed with an "offline-first" approach.
* On subsequent app starts (in the `HomeScreen`), it can be run in async mode. In this
 mode, it first loads the sites from the local cache to provide a fast startup and
 then triggers a background fetch to update the data from the network.
* The local paths to the cached ghost images are stored within the cached sites.json
 file itself, ensuring that the app can always find the necessary offline images.


## Deep dive: image download

1. Initiation: The process starts in the `SitePrefetchScreen`, which calls
`SiteService.fetchSitesAndPrefetchImages()`. This screen is shown after a successful login
to ensure all necessary data is available offline.

2. `sites.json` Fetching:
* The SiteService constructs a URL to the sites.json file located in the organization's
 S3 bucket (e.g., `https://fomomon-data.s3.amazonaws.com/t4gc/sites.json`).
* It uses the http package to make a direct, unauthenticated GET request to download
 this JSON file. This implies that the sites.json file for each organization must be
 publicly readable.
* The downloaded JSON is then cached locally on the device in the application's
 documents directory (`../cache/sites.json`).

3. Ghost Image Fetching (Prefetching):
* After parsing sites.json, the service iterates through the list of sites.
* For each site, it constructs the full URL for the `reference_portrait` and `reference_landscape` images using the `bucket_root` and the image paths from the site data.
* It calls `_ensureCachedImage`, which checks if the image already exists in the local
 cache (`.../ghosts/<siteId>/<imageName>`).
* If the image is not found locally, it is downloaded via a direct, unauthenticated
 HTTP GET request and saved to the cache. Again, this requires the reference images in
 S3 to be publicly readable.

4. Caching and Offline First:
* The SiteService is designed with an "offline-first" approach.
* On subsequent app starts (in the HomeScreen), it can be run in async mode. In this
 mode, it first loads the sites from the local cache to provide a fast startup and
 then triggers a background fetch to update the data from the network.
* The local paths to the cached ghost images are stored within the cached sites.json
 file itself, ensuring that the app can always find the necessary offline images.

## Deep dive: data upload

1. Initiation: The upload process is manually triggered by the user. The
`UploadService.uploadAllSessions()` method is called, which finds all locally stored
sessions that have not yet been uploaded.

2. Authentication Check: For each file to be uploaded (portrait image, landscape image, and
session JSON), the service checks if the user is logged in via
`AuthService.isUserLoggedIn()`.

3. Authenticated Upload (Primary Path):
* If the user is logged in, the service calls `_uploadFileAuth` or `_uploadJsonAuth`.
* It first obtains temporary AWS credentials from the `AuthService`, which, as we know,
 involves the Cognito Identity Pool.
* Crucially, it does not use these credentials to sign a standard HTTP PUT request
 directly. Instead, it uses a `S3SignerService`.
* The `S3SignerService` (which I will infer the behavior of, as it was not provided)
 almost certainly calls the AWS SDK to create a pre-signed S3 PUT URL. This is a
 special, time-limited URL that grants temporary permission to upload a specific
 object to S3.
* The `UploadService` then performs a simple HTTP PUT request to this pre-signed URL,
 with the file's content as the request body. This upload is secure because the URL
 itself contains the authentication signature.
* This is a more secure way to handle uploads than signing every chunk of the request,
 but it still exposes a direct, authenticated link to S3 to the client.

4. Unauthenticated Upload (Fallback/Error Path):
* The code includes `_uploadFileNoAuth` and `_uploadJsonNoAuth` methods, which attempt a
 direct, unauthenticated HTTP PUT to the final S3 URL.
* The comments state this will fail if the user is not logged in, and the code falls
 back to this method if the authenticated, pre-signed URL method fails. This fallback
 path seems problematic and would only succeed if the S3 bucket were configured to
 allow public write access, which would be a major security flaw.

5. Workflow: The service uploads the files in sequence: portrait image, then landscape
image, then the session JSON file (which contains the URLs of the now-uploaded images).
If all three succeed, the local session is marked as uploaded.


## First principles: Do we need an API server?

See [docs/v2/api-server.md](docs/v2/api-server.md)

## Design v2 outline 

__Auth v2 design__

At this point we should consider the investment in cognito. It might be simpler to use password gates that are stored in the apiserver or file system. Basically, use onboarding flow is vastly simplified: 

1. User goes to a page and enters org and email and password. 
2. This kicks off a script that injects these credentials into a file. 
3. The same file is used to authenticate a user.

what we will have to do to go back to the cognito approach is run the `add_user.py` script described in the Authentication deep dive section when the user submits their login form. 

__Config v2 design__

Why do we need configuration? 
1. To tell us which pools to authenticate against in Cognito. But if we introduced an API server, we shouldn't need this. 
2. To tell us where a given org's sites are. 

The second is a valid use case. Whether we download config from s3 or get it from an api, the result will still be the same. We will be storing an orgs sites in a file. And giving that to the app over the net. The app will still have to make similar decisions around whether to retrieve the config or use a cached one. 

What we would like to do, however, is to allow an offline user to navigate to a site. Meaning anyone on the internet should not have access to sites, but the whitelisted users who download the app will all have access to sites whether they login or not. 

That is currently lacking because we stick the login screen up front, and use the login credentials to fetch the configuration. We can leave the login screen as is, but only apply a one time login. Having done this one time login, the org of the user is used to fetch the sites file.

So we can simply leave sites.json config as it is right now. We can just swap one small aspect of it. Instead of storing them on s3 we will store them on local disk of a vm. That way we avoid the permissions issue. But is this worth it? since we already have code to deal with permissions.

Currently, the design is caching and offline first. The problem is the AWS integration leads to complexity. Complexity with the login, signing, fetching and caching - meaning in order to show ghost images to the user we need to access s3 which needs login - but the current design forces the user to login first, downloads a bunch of assets, then re-uses the cached assets till they can login once again. This is actually _better_ than the other two alternatives: 
1. Publicly expose the assets 
2. Require them to login every time

But it is just that it is also more complex (?) 

__Images: v2 design__

Image downloads are Ok to manage on s3. These are just ghost images. 
The problem is not the ghost image download but how users view images on the dashboard. 
In order to show these images to a user, the dashboard needs to access them directly through a signed url which keeps expiring. 
There are a few solutions to this
1. Store images on the vm and send them to the dashboard 
2. Sign urls on the vm and share them with the user based on image paths (on the fly)
3. Sign urls through a cron job which opens up the uploaded config (db.json etc) and reinjects the urls there with newly signed urls every day. 

the third is probably the simplest and doesn't need an extra apiserver. 

__Data upload: v2 design__

Uploading images directly to s3 might be completly OK. 
There is just some transite issue around images getting stuck. The phone seems to keep reflecting that there are 0/2 images to upload - even on new app install. 

__Summary__

So in summary there are two ways to approach the redesign, and we need to choose one. 

1. Accept that the current app does a lot of things well. Basically it is 80% there, and what's missing is some bug fixing and screen re-ordering around auth/image fetching/caching. Some of these issues would happen anyway, even with an api server. 

2. Continue to use aws for s3 storage and hence iam permissions but decouple auth from cognito. Add a apiserver hop inbetween. The apiserver will still read and write to s3, but only it is allowed to do so. Everything on the app functionally remains the same, sites.json is still returned, ghost image urls are still returned etc. But they go through the apiserver and the apiserver translates the user login to aws iam. 

We can choose 2. 

For every touch point that the current app has with aws/s3/cognito, we will instead pipe it into an apiserver. This apiserver will store the files directly on disk. In addition, there will be a cron job that runs hourly and offloads this data to s3. It will sync any new data to s3, sync that data to db.json. Re-generate signed urls etc. However the apiserver will keep serving data from its local store. This also applies to sites.json and the ghost images. So the apiserver will have to use the local filesystem layout to identify a given orgs ghost images, questionnaires etc. 

__Future work__


Further more there will be a few different interfaes. 
1. An interface to view the images. This already exists. It will read the uploaded db.json and show the images. These are the links the hourly cron jobs keep regenerating. 
2. An interface to on-board a user. This will have to add the users name/password/org to a local sites.json. 
3. An interface to add a new site, this allows us to add the lat/lon of a new site, name it, supply its ghost image etc. This should modify an org's sites.json. 
4. Furthermore, when the user tries to add a new site via the phone app, it will have to call the addSite endpoint. There is already add site logic in the app. But currently, those sits aren't integrated into the sites.json on s3. 
5. An finally an interface to add an experiment. This can be a wizard walkthrough that asks the user for each site, calls add site, then asks the user for a description of the experiment. 

This is not for current implementation, just to future proof the API server. 

__Future integrations__

As we think about 2 aspects of this
1. Integration with Tarkam / CKAN for user auth. 
2. Integration with a plantwise for consolidation of data handling. 

Regarding the plantwise design

```
Backend and automation: Build an automated backend pipeline that allows moderators
or project owners to directly upload new datasets (species occurrences, nursery
inventories, or environmental layers) through a simple web-based interface. Once
uploaded, the system will automatically trigger the modeling workflow (e.g.,
MaxEnt-based SDMs), process the data, retrain models as needed, and update the
output files stored on the cloud. The frontend will then fetch these updated outputs
dynamically, ensuring that end-users always access the most current information. This
integration will eliminate repeated manual steps, reduce maintenance costs, and make
PlantWise scalable for larger datasets and wider geographic coverage.
```

1. Cleanup
2. Ingestion of new datasets (`Species name, lat, long` list deduped into `Full_Species.csv`)
3. Ingestion of new env layers like worldclim format
4. Retraining (run maxent on processed `Full_Species.csv`)
5. Serving 

It will do exactly what the current model does, but no improvements. 
Q1 target. 

