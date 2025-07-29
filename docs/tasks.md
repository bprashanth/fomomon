
## Issues 

1. We don't re-fetch reference images, but we should if the timestamp is different. Alternatively, we can always modify the reference images to point at images that have a different file name (i.e a different timestamp in the filename itself) so it will _always_ differ.

2. Errors in pre-fetch

3. Scaling images (see [docs/aspectratio](./aspectratio.md))

4. Don't block home screen on prefetching - users in the field must be allowed to run multiple pipelines. Currently we try to re-fetch in home screens init. 

5. Auth
	- script: limits on iam roles in aws 
	- script: GC roles against buckets in the bucket change case  
	- currently the base bucket starts off as public read no write. Running
	  `add_uses.py` makes this per-org read/write. Instead we should keep
`fomomon/*` public except for prefixes (eg adding a new org adds this org to
the `Deny` list in the root bucket policy). OR we can make fomomon public for
root assets only, not `fomomon/*` wildcard. Needs some thought. 

6. First image is without ghost. The how do users set a ghost? Avoid confusion, just don't set one at first. 

7. Metrics and consolidated logging 

8. URLs and repeatability: if a session or image is uploaded to some url, and there is an app crash before we can mark the session as uploaded, will the next url created for the same session be different or the same? do we need to garbage collect stray images/sessions in s3? 

9. GPS accuracy: what happens if we don't get an accurate stream in the field? can we detect motion anyway and flag this to the user? see fomonon/pull/11 for details 

10. Marking files as uploaded: currently we just mark local sessions as uploaded instead of deleting them. This is a safeguard. While we will only ever re-upload un-uploaded files, as long as the file exists locally, we can push an app update that re-uploads all of them. While this gives us data safety, it is also a "memory leak". When we decide to GA we should add some scripting that will delete all stale files. 

11. Upload errors: we should flag upload errors as more approachable UI errors. Currently we just log it, we should at least show a snackbar. 

12. Timestamps: we use timestamps in file names to make them unique. Unfortunately this can backfire with clock skew on a phone. 

### Tech Debt

1. Refactor routes into named routes, ideally we would have centralized routing and invoke the pipeline like so
```
Navigator.of(context).pushReplacementNamed(
  '/capture_landscape',
  arguments: ConfirmScreenArgs(...),
);
```
2. Extract orientation logic into an OrientationService (see [code.md reentry](code.md)).
3. Find a cleaner way to manage global state instead of threading through the pipelien 
	- Current method only works for few screens
	- A better alternative is to use a `UserSession` singleton
```
class UserSession {
  static String name = '';
  static String email = '';
  static String org = '';

  static void set({required String n, required String e, required String o}) {
    name = n;
    email = e;
    org = o;
  }
}
UserSession.set(name: name, email: email, org: org);
final org = UserSession.org;
```
4. Clean up HomeScreen. It's currently got too many stacks in its build method. 


### Thought issues 

1. Errors while uploading images. There might be races around uploading an image, replacing the image path in the session data structure and deleting the local image. Not sure if this is a big issue, we can order it as upload, write to session object, delete image. 


## Outline
```
Step 1: Create CapturedSession model
Store all capture info + responses
Make Hive-compatible

Step 2: Build CaptureScreen for portrait
Ghost overlay + opacity slider
Save image to local path
Navigate to ConfirmScreen

Step 3: Add ConfirmScreen
Show image
“Retake”: go back
“Next”: continue

Step 4–6:
Repeat for landscape
Show SurveyScreen
Save session to Hive

Step 7:
Build GalleryScreen to list local sessions
Add "Upload All" button

Step 8:
Build UploadService:
Upload image files to S3
Upload metadata JSON
Delete session on success
```

## Site Entry (0.5 days)

* Add a large "+" when near a site 
* Tapping it launches the pipeline

## Capture pipeline (2 days)

1. Step 1: Landscape photo with ghost overla
2. Step 2: Portrait photo with ghost overlay
3. Step 3: Survey questions from site config
4. Step 4: Save local session (JSON + image paths)

## Local Session (1 day)

Via hive

* Use unique IDs for session files
* Keep files in db/ directory until upload
* Include metadata: site_id, timestamp, user info, etc.

## Upload Logic (1 day)

* Upload button on Home or Upload screen
* Only delete session after full upload succeeds

## Sync and Refresh (0.5 day)

* Poll sites.json and suers.json daily



