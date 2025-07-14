

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

1. HomeScreen
2. CaptureScreen
3. ConfirmScreen
4. SurveyScreen
5. ReviewScreen
6. GalleryScreen
7. UploadScreen


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

Stored in this manner 
```
your-bucket/
├── sites.json
├── users.json
├── db/
│   ├── 2025-07-14_1005.json  
│   ├── 2025-07-14_1130.json
│   └── ...
├── site_001/
│   ├── 2025-07-14_1005_portrait.jpg
│   ├── 2025-07-14_1006_landscape.jpg
```
* There is only one sites file per all users in an org, and it captures all sites info. 
* Each db fil
e is a batch of session data captured on one phone, covering one or more sites, and one single upload action. 

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

### App local storage management 

We use a singleton SessionManager for the local storage.
Local storage is in `hive`. 

### S3 storage management 

1. Upload images 
2. Replace local paths in session metadata with s3 urls
3. Read db.json from s3
4. Append session metadatas
5. PUT db.json


## Location logic 

We use the `geolocator` plugin to do the following 
1. Periodically check location
2. Compare distance with every site in array
3. Show golden ring around the "+" button within 10m 
4. Visual feedback should be instantaneous


## Capture interface 

3 aspects of this
1. Camera 
2. Stack the ghost image 
3. Slider for opacity 

We do this in both portrait and landscape mode. 

## Survey UI 

Simple list of text, radio buttons depending on `SurveyQuestion.type`
Final submit button closes and saves teh session 

## Client side syncing 

Simple fetch every 24h of sites.json and users.json

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

## Uploads and Sync 

* Atomic uploads 
	- Store each session locally in Hive.
	- Only delete sessions after successful upload (all images + JSON).
	- No need for an uploaded flag.
	- UI can just show all current local sessions. If it’s not there, it’s
	  uploaded. If it’s there, it’s pending.

