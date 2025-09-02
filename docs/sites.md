# Fetching and processing sites 

* Sites are fetched once between the login and home screen, and again on the home screen. 
* It's done twice because the first screen (`site_prefetch_screen`) only runs on login, and is meant to indicate to the user that some background fetching is happening. 
* However we will need to keep refreshing sites in case sites are added in the backend periodically, so we do that everytime the user navigates back home. 
* This home screen sites fetching is currently _blocking_. 

So the issue here is three fold 
1. If there is good internet - unlikely, as the only case where home screen refresh triggers is when theyre in the field - fetching sites does what we want 
2. If there is no internet - the current fetch-over-network code will fail, and return the cached sites 
3. If there is _flaky_ internet - the current fetch-over-network code will hang and prevent the user from proceeding


## Caching 

Sites are cached. This is done so the user doesn't block on the home screen when offline. 
Every successful network request automatically caches `sites.json`.
On fetching sites error, the app reuses the cached sites. 
The cache directory is `{app_documents}/cache/sites.json`

## Local sites 

We allow the user to create local sites. These sites are stored in a separate `application directory/local_sites.json` file and merged with the cached remote sites during upload time. We need to do this because each session is tagged with a site id, and if no site matches the id, the session is not updated. 

Once the session is uploaded we need to merge the new site back into sites.json so that on next pull, the user sees the new site with a ghost image. 

What will happen if the user re-visits the same site before we merge it back into sites.json? the site should get deduped. Meaning you can re-add the site and it should "upsert" and allow you to capture and upload the session. 

Remote sites get precedence over local ones when there is a conflict deduped on the site id. 

## Site selection flow 

2 main options
1. Choose existing site 
2. Create New site 

only one option can be selected at a time, and the continue button is only enabled when a valid selection is made. For the new site: 

1. Current GPS is used 
2. Copied from "nearest site"
	- questions
	- bucket root
3. Saves this site to local storage
4. Passes this new site onto the session creation pipeline 

## Where are local sites images uploaded? 

* Path: `{selectedSite.id}/{userId}_{timestamp}_{orientation}.jpg`
* Bucket: `selectedSite.bucketRoot`

So if a user creates a new local site called `new_site_001`, the images will be uploaded to:
* `new_site_001/user123_20250115T143000_portrait.jpg`
* `new_site_001/user123_20250115T143000_landscape.jpg`
The bucket root comes from the selected/created site, not necessarily the nearest site (though for new local sites, we copy the bucket root from the nearest site).
