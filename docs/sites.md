# Fetching and processing sites 

* Sites are fetched once between the login and home screen, and again on the home screen. 
* It's done twice because the first screen (`site_prefetch_screen`) only runs on login, and is meant to indicate to the user that some background fetching is happening. 
* However we will need to keep refreshing sites in case sites are added in the backend periodically, so we do that everytime the user navigates back home. 
* This home screen sites fetching is currently _blocking_. 

So the issue here is three fold 
1. If there is good internet - unlikely, as the only case where home screen refresh triggers is when theyre in the field - fetching sites does what we want 
2. If there is no internet - the current fetch-over-network code will fail, and return the cached sites 
3. If there is _bad_ internet - the current fetch-over-network code will hang and prevent the user from proceeding


## Caching 

Sites are cached. This is done so the user doesn't block on the home screen when offline. 
Every successful network request automatically caches `sites.json`.
On fetching sites error, the app reuses the cached sites. 
The cache directory is `{app_documents}/cache/sites.json`

