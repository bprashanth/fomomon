# Sessions and db.json

The `db.json` file within an orgs bucket (i.e the `db.json` within `fomomon/ncf/`) is essential to display data on the frontend. If it doesn't exist, the org will simply see the "upload files" ux. This is how it's generated. 

* Each run of the pipeline creates a local sessions.json file on the phone. This sessions.json file has local paths to images. 
* When the user hits the upload button, these local images are uploaded to s3 (if the user has logged in, we know their org and upload to `bucketroot/org`, if we don't know their org - i.e. this is guest mode - we still upload to bucket root from `sites.json`, but the hardcoded `sites.json` for guest mode will point at a public fomomon guest bucket). 
* The aws links to these images are then written to `sessions.json`, and the `session.json` objects are uploaded to `bucketroot/org/sessions`
* At this point, the data _will not_ show up on the dashboard. The only way to retrieve the data is by downloading it directly from s3. 

To get these sessions to show up on the dashboard, we will have to run the `hack/s3/create_db.py` script
```
$ python3 ./create_db.py --root-bucket s3://fomomon/ncf/ --sites-config ../../config/sites/guest.json --output-path db.json
```
And upload `db.json` to `bucketroot/orgname/db.json`



