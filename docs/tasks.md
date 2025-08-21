
## Issues 

1. We don't re-fetch reference images, but we should if the timestamp is different. Alternatively, we can always modify the reference images to point at images that have a different file name (i.e a different timestamp in the filename itself) so it will _always_ differ.

2. Errors in pre-fetch

3. Scaling images (see [docs/aspectratio](./aspectratio.md))

4. Don't block home screen on prefetching - users in the field must be allowed to run multiple pipelines. Currently we try to re-fetch in home screens init. 
	- Refactor `site_servcie.dart` for reuse in background and foreground prefetchers. 
5. Auth
	- login code is exception city, clean it up but retain clarity 
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

13. Crash reporting/analytics 

### High priority: Exceptions and observability 

1. There is some weird camera GC issue that happens when we cycle the pipeline and return to the home screen, logs show  - this is leading to delay in home screen loading 
```
W/LegacyMessageQueue(18205): java.lang.IllegalStateException: Handler (android.os.Handler) {5f24343} sending message to a Handler on a dead thread
W/LegacyMessageQueue(18205):    at android.os.MessageQueue.enqueueMessageLegacy(MessageQueue.java:1291)
W/LegacyMessageQueue(18205):    at android.os.MessageQueue.enqueueMessage(MessageQueue.java:1400)
W/LegacyMessageQueue(18205):    at android.os.Handler.enqueueMessage(Handler.java:790)
W/LegacyMessageQueue(18205):    at android.os.Handler.sendMessageAtTime(Handler.java:739)
W/LegacyMessageQueue(18205):    at android.os.Handler.sendMessageDelayed(Handler.java:709)
W/LegacyMessageQueue(18205):    at android.os.Handler.post(Handler.java:439)
W/LegacyMessageQueue(18205):    at android.hardware.camera2.impl.CameraDeviceImpl$CameraHandlerExecutor.execute(CameraDeviceImpl.java:2839)
W/LegacyMessageQueue(18205):    at android.hardware.camera2.impl.CameraDeviceImpl$ClientStateCallback.onClosed(CameraDeviceImpl.java:348)
W/LegacyMessageQueue(18205):    at android.hardware.camera2.impl.CameraDeviceImpl$7.run(CameraDeviceImpl.java:301)
W/LegacyMessageQueue(18205):    at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1156)
W/LegacyMessageQueue(18205):    at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:651)
W/LegacyMessageQueue(18205):    at java.lang.Thread.run(Thread.java:1119)
```

2. LocalSessionStorage should be mindful of orgnames 
	- this is required because we currently assume only 1 org uses 1
	  phone, so if the phone's user switches orgs the sites.json for
the second org won't contain the location of the recorded data 
	- the real fix here is to namespace sessions with the org on
	  local phone disk 


3. Logging x observability through firebase free tier 

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

5. Combine scripts in `hack/` into utility script with verbs, like `kubectl`. Maybe call it `fomoctl` and it should haveverbs like `get,list,create`.

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



