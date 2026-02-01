# Persistent Login Design

## Overview

This document explains the design and implementation of persistent login using Cognito refresh tokens. The goal is to allow users to access the app offline after device reboot, using the stored refresh token as a "has logged in" flag to bypass the login screen.

## Problem Statement

Previously, if the app was terminated or the device rebooted in an offline environment, users were logged out and couldn't re-enter the app to capture data. All work was blocked until a network connection was available to log in again.

## Solution: Refresh Token Persistence

We store the Cognito refresh token securely using `flutter_secure_storage`, which provides OS-level encryption (iOS Keychain, Android Keystore). The token acts as a boolean flag when offline, allowing users to bypass login and continue working with cached data.

## Architecture: Session, Token, and Credential

### Session (CognitoUserSession)

A `CognitoUserSession` object contains three JWT tokens:

1. **ID Token**: Short-lived JWT (~1 hour) that proves user identity. Used to exchange for AWS credentials via Cognito Identity Pool.
2. **Access Token**: JWT for API authorization (not used in this app).
3. **Refresh Token**: Long-lived token (~30 days) used to obtain new ID/Access tokens. **This is the token we persist securely.**

### Token (JWT Strings)

- **Refresh Token**: Stored securely in `flutter_secure_storage`. Acts as a "has logged in" boolean when offline.
- **ID Token**: Obtained by calling `user.refreshSession(refreshToken)`. **This always makes a network call to Cognito**, even if the current ID token isn't expired. The SDK doesn't cache - it always validates with Cognito.

### Credential (AWS Temporary Credentials)

AWS temporary credentials (`accessKeyId`, `secretAccessKey`, `sessionToken`) obtained by exchanging the ID token with Cognito Identity Pool. These are **NOT** sent as HTTP bearer headers. Instead, they're used to sign S3 requests via presigned URLs.

## Authentication Flow

### Login Flow

1. User enters credentials in `LoginScreen`
2. `AppConfig.configure()` is called with org selection
3. `AuthService.login()` authenticates with Cognito
4. On success, `CognitoUserSession` is created with ID/Access/Refresh tokens
5. Refresh token, username, and org are stored securely
6. User navigates to `SitePrefetchScreen` → `HomeScreen`

### App Restart/Reboot Flow (Offline)

1. `app.dart` calls `AuthService.restoreSessionOffline()` on startup
2. `restoreSessionOffline()` reads stored refresh token, username, and org from secure storage
3. If token exists, returns user info (username, org) **without creating a full session object**
4. App configures itself with stored org and navigates directly to `HomeScreen`
5. User can work offline using cached sites/images
6. **No network calls are made** - auth config is not fetched, full session is not created

**Why defer full session restoration?** Creating a full `CognitoUserSession` requires:
- Fetching auth config from S3 (network call)
- Creating `CognitoUser` object (needs auth config)
- Calling `refreshSession()` to validate refresh token (network call to Cognito)

By deferring this until upload time, we achieve offline-first access: users can immediately use the app after reboot without waiting for network calls. The stored refresh token acts as a "has logged in" boolean to bypass the login screen. Full session restoration happens in `getValidToken()` when upload is attempted (which requires network anyway).

### Upload Flow (When Network Available)

1. User attempts upload → `UploadService.uploadAllSessions()` is called
2. `uploadAllSessions()` calls `AuthService.getUploadCredentials()`
3. `getUploadCredentials()` calls `getValidToken()`:
   - If no session exists, fetches auth config (network call)
   - Uses stored refresh token to call `user.refreshSession()` (network call to Cognito)
   - Returns fresh ID token (JWT string)
4. `getUploadCredentials()` exchanges ID token with Cognito Identity Pool (network call)
5. Returns AWS temporary credentials
6. Credentials used by `S3SignerService` to create presigned URLs for uploads

## Key Design Decisions

### 1. Offline-First Approach

- Token existence check only - no validation until upload attempt
- Auth config fetching deferred until upload (which requires network anyway)
- User can capture sessions completely offline

### 2. Bypass Prefetch on Restore

When restoring session, we skip `SitePrefetchScreen` and go directly to `HomeScreen`. This allows immediate offline access using cached sites/images.

### 3. Error Handling

Expired tokens throw `AuthSessionExpiredException` that the UI can catch and handle gracefully, redirecting to login screen.

### 4. Storage Strategy

- Username and org stored alongside refresh token to restore app state without network
- All stored in `flutter_secure_storage` (OS-encrypted)
- Storage pattern is backend-agnostic - only the refresh mechanism would need to change if swapping auth backends (e.g., Firebase Auth)

## Implementation Details

### Secure Storage

- Uses `flutter_secure_storage` package
- iOS: Keychain Services (encrypted by iOS, hardware-backed on newer devices)
- Android: EncryptedSharedPreferences (AES encryption) or Android Keystore
- Encrypted at rest by the OS until device unlock

### Session Restoration

`restoreSessionOffline()` method:
- Reads stored refresh token, username, and org from secure storage
- Returns user info if token exists (acts as boolean to bypass login)
- Creates a "thin" session with only user info, NOT a full `CognitoUserSession`
- Does NOT create `CognitoUser` or full session object (deferred until upload)
- Does NOT fetch auth config (deferred until upload)

**Why offline-only restoration?** Full session restoration requires network calls (fetching auth config, validating refresh token with Cognito). By deferring this to upload time, we enable immediate offline access after reboot. The stored refresh token serves as a "has logged in" flag, and full session restoration happens lazily in `getValidToken()` when network operations are needed.

### Token Refresh

`getValidToken()` method:
- Checks if session exists and is valid
- If not, uses stored refresh token to call Cognito
- Always makes network call to Cognito (no caching)
- Updates stored refresh token if it changes
- Throws `AuthSessionExpiredException` if refresh fails

### Credential Exchange

`getUploadCredentials()` method:
- Gets valid ID token via `getValidToken()`
- Creates `CognitoCredentials` instance
- Exchanges ID token with Cognito Identity Pool for AWS credentials
- Returns temporary credentials (valid for ~1 hour)

## Testing

### Normal Flow

1. Login once - token stored
2. Reboot device - app bypasses login, goes to HomeScreen
3. Capture sessions offline
4. When network available, upload works seamlessly

### Expired Session Testing

There are several ways to test expired/corrupted token scenarios:

#### Method 1: Clear All App Data (Easiest)
This clears all app data including secure storage, simulating a fresh install:

The following assumes you built the app with `flutter run --flavor alpha`, if you used `--flavor dev` then stick `.dev` instead of `.alpha`

```bash
adb shell pm clear com.t4gc.fomomon.alpha
```

Then restart the app - it should show the login screen.

#### Method 2: Clear Only Secure Storage (More Targeted)
Use `run-as` to access the app's private directory without root:

**Important:** `flutter_secure_storage` on Android creates TWO files:
- `FlutterSecureStorage.xml` - Contains encrypted values
- `FlutterSecureKeyStorage.xml` - Contains encryption keys/metadata

You need to delete BOTH files to fully clear secure storage:

```bash
# Check what secure storage files exist
adb shell run-as com.t4gc.fomomon.alpha ls -la shared_prefs/ | grep -i secure

# Delete both secure storage files
adb shell run-as com.t4gc.fomomon.alpha rm shared_prefs/FlutterSecureStorage.xml shared_prefs/FlutterSecureKeyStorage.xml

# Verify they're deleted
adb shell run-as com.t4gc.fomomon.alpha ls -la shared_prefs/ | grep -i secure
```

**Note:** If the app still finds tokens after deleting both files, `flutter_secure_storage` might be using Android Keystore (hardware-backed encryption). In that case, use Method 1 (`pm clear`) which clears all app data including Keystore entries.

Then restart the app (or just kill and reopen it) - it should show the login screen.

#### Method 3: Corrupt the Token Value (Test Expired Token Flow)
If you want to test the expired token flow specifically (where token exists but is invalid):

```bash
# First, find the stored token key (flutter_secure_storage uses encrypted storage)
# The actual key name is prefixed, but you can clear all secure storage:
adb shell run-as com.t4gc.fomomon rm -rf shared_prefs/FlutterSecureStorage.xml

# Or if you want to test expired token without clearing, you'd need to:
# 1. Login normally
# 2. Use ADB to manually edit the encrypted storage (complex)
# 3. Or wait 30 days for natural expiration
# 4. Or modify the code temporarily to use an expired token
```

#### Method 4: Test During App Runtime (Without Restart)
To test while the app is running, you can:

1. Clear secure storage using Method 2 above
2. In the app, trigger an upload (which calls `getValidToken()`)
3. The app should catch `AuthSessionExpiredException` and redirect to login

**Note**: `flutter_secure_storage` on Android may also use Android Keystore for encryption keys. If Method 2 doesn't work, try Method 1 (clear all app data) which will definitely clear everything.

## Future Considerations

- Token expiration: Currently 30 days. User will need to re-login after expiration.
- Backend-agnostic: Storage pattern works with any auth backend. Only refresh mechanism needs to change.
- Security: Refresh tokens are stored securely but can be extracted from rooted/jailbroken devices. Consider additional security measures if needed.

