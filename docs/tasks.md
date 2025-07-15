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


## Issues 

1. We don't re-fetch reference images, but we should if the timestamp is different. Alternatively, we can always modify the reference images to point at images that have a different file name (i.e a different timestamp in the filename itself) so it will _always_ differ.
