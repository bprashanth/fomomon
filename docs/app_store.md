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

## App versions 

We use `semver` or semantic versioning for app versions. 

The format is `versionCode (semver)`

1. The `semver`: This takes the form of `major.minor.patch`, plus a pre-release tag like `-alpha` or `-beta`. 
2. The `versionCode`: must increase every single upload. 

### Bumping semver versions 

* Major (1.x.x) – Big launches, breaking changes.
* Minor (x.1.x) – New features, backward-compatible.
* Patch (x.x.1) – Bug fixes, hotfixes.

In pubspec.yaml, this maps to 
```yaml
version: 1.0.0+1
```
Which is the `semver` + `versionCode`. 

### Example progression
```console
1.0.0+1 -> initial alpha
1.0.1+2 -> hotfix in alpha
1.1.0+3 -> beta release
1.1.1+4 -> patch in beta
1.0.0+5 -> public release
```
These values are _automatically parsed_ out of the `.aab` file uploaded to the playstore. They enter the `.aab` file via `build.gradle`, which is configured with the appropriate `flutter run --flavor dev` type command (see [release channels](../docs/release_channels.md) for details. 

However, for the `build.gradle` to be updated, you must bump up the value in `pubspec.yaml`. 


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

 
