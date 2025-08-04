# FAQs regarding the app store 

## App naming 

* Package name: this is the fqdn 
	- testing: `com.t4gc.fomomon.testing`
	- prod: `com.t4gc.fomomon`
* App name: this is the display name, can be changed anytime in the console 

## App signing

The point of signing as far as google is concerned is simply to demonstrate
that no one has tampered with your app. You generate a key pair, you sign with
the private key, and you give google the public key to verify the signature
against the app contents. 

Basically the way this works is, a key is generated and stored on disk 
```console 
$  keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
$ ls 
android/
  app/
    build.gradle
    upload-keystore.jks
    key.properties
```
And the file `key.properties` points to `upload-keystore.jks`
```
storeFile=upload-keystore.jks
```
Which is consumed in `build.gradle` as 
```python
storeFile file(keystoreProperties['storeFile'])
```
And used to sign release builds when we run 
```console 
flutter build apk --release 
flutter build appbundle --release 
```

## Key management 

This section is regarding how we manage keys for app signing. 
There are 2 keys: 
1. Upload keys 
2. Production keys 

These keys are generated using the variables in `key.properties`, and all three (the keys, the `upload-keystore.jks` and `key.properties`) are backed up to team GDrive. 

It is important to note that there are 2 signing operations:    
1. Play App signing _is_ enabled, so the play store signs the app before sending it to users. This key is what `storePassword` is referencing. 
2. _You_ as the developer need to sign the app pre-Play Store upload. 

If you lose 2, you can reset it. And 1 is backed up by the playstore. 

## Privacy Policy 

We need a privacy policy describing: 
1. Permissions of the app (GPS, camera, login) 
2. Disclosure of data we collect, usage and sharing 
3. This needs to be shared via a link on the play console + a link on the app 


 
