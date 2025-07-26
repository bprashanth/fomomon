# Uploading sessions 

1. Read all local and un uploaded CapturedSession files 
2. For each session
- upload images: 
	`portraitImagePath` -> `site_id/{userId}_{timestamp}_portrait.jpg`
	`landscapeImagePath` -> `site_id/{userId}_{timestamp}_landscape.jpg`
- Replace paths in the CapturedSession objects with the S3 URLs (this happens in-memory)
3. Upload the modified session JSON into `sessions/{userId}_{timestamp}.json`
4. Mark the local sessions as "uploaded" 

The decision to upload sessions separately was made to keep things simple.

1. Avoids s3 write conflicts 
2. Uploads from the phone are atomic and recoverable (i.e recovery means keeping the session files on the phone, and simply re-uploading them)
3. Merges of all users' session files into one checkpoint/db file can be done via lambda or script

Errors in uploading are managed by simply _not_ writing the "uploaded" bit so the session manager returns the session the next time around. This is also why we retain the local-path-sessions on disk instead of overwriting it with the modified with-url sessions. 


## Tooling 

Run 
```
$ ../hack/s3_bucket.sh --help
```

To see options. This tool allows you to 
1. Create a bucket 
2. Enable/Disable public write on it (for testing) 
3. Write files to specific paths 

Eg marking a bucket public write 
```
$ ./hack/s3_bucket.sh --bucket_name fomomon --public-write false
$ curl -X PUT --upload-file ./assets/images/loading.png   -H "Content-Type: image/png"   https://fomomon.s3.amazonaws.com/t4gc/loading.png
```

## Merging sessions into a db	

TBD

## Moving the db file into an actual db

TBD

## DB backups 

TBD
