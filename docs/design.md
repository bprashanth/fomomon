# Fomomon


## Pipeline 

```
	Detect proximity → Enable "+" button
	|
	User taps "+"
	|
	Portrait capture screen
	|
	Ghost overlay
	Opacity slider
	Capture button
	|
	Portrait confirm screen
	Show image without ghost
	Options: Retake / Next
	|
	Landscape capture screen
	|
	Landscape confirm screen
	|
	Survey screen
	|
	Local save
	|
	Upload (manual button press)
```

## UI components 

1. LoginScreen
2. SitePrefetchScreen
3. HomeScreen
4. CaptureScreen
5. ConfirmScreen
6. SurveyScreen
7. ReviewScreen
8. GalleryScreen
9. UploadScreen


## Data Structures and storages 

There are 3 main json files: 
1. sites.json
2. db.json 
3. users.json

sites.json is where we add new sites. 
```
{
  "bucket_root": "https://your-bucket.s3.amazonaws.com/",
  "sites": [
    {
      "id": "site001",
      "location": { "lat": 10.123, "lng": 76.456 },
      "creation_timestamp": "2023-07-10T08:00:00Z",
      "reference_portrait": "site001/portrait_ref.png",
      "reference_landscape": "site001/landscape_ref.png",
      "survey": [ ... ]
    }
  ]
}
```
db.json is where we add uploaded images. 

```
{
  "bucket_root": "https://your-bucket.s3.amazonaws.com/",
  "sessions": [
    {
      "site_id": "site001",
      "timestamp": "2025-07-14T10:15:00Z",
      "gps_coords": { "lat": 10.12345, "lng": 76.54321 },
      "portrait_image_url": "site001/2025-07-14_1015_portrait.jpg",
      "landscape_image_url": "site001/2025-07-14_1016_landscape.jpg",
      "survey_responses": [
        { "question_id": "q1", "answer": "Yes" },
        { "question_id": "q2", "answer": "3 monkeys" }
      ],
      "user_id": "john_singh",
    }
  ]
}
```
and users.json where we record users / org
```
{
  "bucket_root": "https://your-bucket.s3.amazonaws.com/",
  "users": [
    {
      "user_id": "john_singh",
      "name": "John Singh",
      "email": "john@example.com"
    },
    {
      "user_id": "lakshmi_n",
      "name": "Lakshmi Narayan",
      "email": "lakshmi@ngo.org"
    }
  ]
}
```

Stored in this manner remotely
```
s3://bucket/org/
├── sites.json
├── users.json
├── site_001/
│   ├── {userId}_{timestamp}_portrait.jpg
│   └── ...
├── db/
│   └── {userId}_{timestamp}.json
```
* There is only one sites file per all users in an org, and it captures all sites info. 
* Each db file is a batch of session data (though it could be the output of a single pipeline as well) captured on one phone, covering one or more sites, and one single upload action. 
* These db files are stored locally as 
```
documents/
├── images/
│   ├── site_001/
│   │   ├── {userId}_{timestamp}_portrait.jpg
│   │   └── {userId}_{timestamp}_landscape.jpg
├── sessions/
│   ├── {userId}_{timestamp}.json
```

Where `documents` is what's returned by `getApplicationDocumentsDirectory`.

### Models 

The main model for `db.json` is a data packet for the `CapturedSession`

```json
class CapturedSession {
	final String siteId;
	final LatLng capturedLocation;
	final String portraitImagePath;
	final String landscapeImagePath;
	final List<SurveyResponse> responses;
	final DateTime timestamp;
	bool isUploaded;
}
```

And for `sites.json` is't a `Site`
```json
class Site {
	final String id;
	final LatLng location;
	final String referenceImageUrl;
	final List<SurveyQuestion> survey;
	final double radius; // 10m default
}
```

And the surveys are structured as a list of question/answer 
```json 
class SurveyQuestion {
	final String id;
	final String question;
	final String type;
	final List<String>? options;
}

class SurveyResponse {
	final String questionId;
	final String answer;
}
```

The `SurveyQuestion` object is part of `sites.json`, since it's configured only once at source. However survey questions can be different per site. The `SurveyResponse` is captured once per pipeline. So it's part of the `CapturedSession` data structure. 

## Location logic 

See [motion doc](./motion.md). In summary we use the `geolocator` plugin to do the following 
1. Periodically check location
2. Compare distance with every site in array
3. Show golden ring around the "+" button within 10m 


## Capture interface 

3 aspects of this
1. Camera 
2. Stack the ghost image 
3. Slider for opacity 

We do this in both portrait and landscape mode. 
There are some tricky aspects of how we pipeline the capture interfaces with the confirmation screens. See [code doc](./code.md).

## Client side syncing 

We have decided to sync at 2 places: 

1. Post login, through an explicity `site_prefetch_screen`. This is so the user doesn't immediately plop into a pipeline and end up with an error saying "ghost image unavailable". 
2. In the init of every home screen.

2 is triggered everytime the user finishes the pipeline. But 2 is a "best effort" sync, meaning if there is no network, we ignore and carry on so the user can save multiple pipeliens back to back. 

Simple fetch every 24h of sites.json and users.json is option 2. 

## Survey UI 

Simple list of text, radio buttons depending on `SurveyQuestion.type`
Final submit button closes and saves teh session 

## Multi-org/user support 

Currently this is managed as directories in s3
```
fomomon-data/
├── ncf/
│   ├── sites.json
│   ├── users.json
│   ├── db/
│   └── site001/
├── wti/
│   ├── sites.json
│   ├── users.json
│   ├── db/
```

In the login flow we ask for: login name or email + org code and reconstruct using 
```
bucketRoot = "https://fomomon-data.s3.amazonaws.com/$org/"
```

### App local storage management 

We use services for the local storage. 

### S3 storage management 

1. Upload images 
2. Replace local paths in session metadata with s3 urls
3. Upload all session.jsons into the `db/` directory

## Uploads and Sync 

* Atomic uploads 
	- Store each session locally. 
	- Only delete sessions after successful upload (all images + JSON).
	- No need for an uploaded flag.
	- UI can just show all current local sessions. If it’s not there, it’s
	  uploaded. If it’s there, it’s pending.

