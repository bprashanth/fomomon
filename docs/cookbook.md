## Creating test sites 

Generate the content 
```shell
$ source venv/bin/activate
$ python3 hack/generate_sites.py
```

Create the s3 bucket 
```console 
# Create root bucket 
$ hack/s3_bucket.sh --bucket_name fomomon --create

# Upload image to org foo, site bar 
$ ./hack/s3_bucket.sh --bucket_name fomomon --path t4gc/users.json --file ./examples/users.json
$ ./hack/s3_bucket.sh --bucket_name fomomon --path t4gc/sites.json --file ./examples/sites.json
$ ./hack/s3_bucket.sh --bucket_name fomomon --path t4gc/test_site_001/image.jpg --file ./examples/image.jpg
```

## Testing 

See comments in main.dart 
```
  // Uncomment for test mode
  // AppConfig.isTestMode = true;
  // AppConfig.setLocalRoot("file:///storage/emulated/0/Download/fomomon_test/");
  // AppConfig.mockLat = 12.9719;
  // AppConfig.mockLng = 77.5937;
```
You can remove setLocalRoot and position mockLat/Lng to be close to one of the s3 sites too. 
