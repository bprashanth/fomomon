# Pre-Redesign Task List

This document outlines critical fixes to stabilize the current version of the Fomomon app before beginning the larger v2 redesign. The goal is to address major user experience issues with minimal, targeted changes.

---

## 1. Offline Authentication and Session Persistence

### Issue

The application currently requires a network connection to log in. If the app is terminated or the device is rebooted in the field (an offline environment), the user is logged out and cannot re-enter the app to capture data. All work is blocked until a network connection is available to log in again.

### Proposed Fix

Implement a persistent session mechanism that allows users to re-enter the app offline if they have logged in successfully at least once.

1.  **Persist Session on Login**:
    *   Upon a successful login in `login_screen.dart`, securely store essential, non-sensitive session information locally. This includes the `username`, `org`, and the **Cognito Refresh Token**.
    *   **Files to Modify**: `fomomon/lib/screens/login_screen.dart`, `fomomon/lib/services/auth_service.dart`.
    *   **Dependencies**: Use the `flutter_secure_storage` package to store the refresh token securely. Add it to `pubspec.yaml`.

2.  **Restore Session on App Start**:
    *   In `main.dart`, before the `FomomonApp` is run, add a startup routine that checks for a stored refresh token.
    *   If a token exists, initialize `AuthService` with this token and navigate the user directly to `HomeScreen`, bypassing the `LoginScreen`. The user is now in a "presumed-authenticated" state.
    *   `AuthService` will need a new method, e.g., `restoreSession(String refreshToken)`, to re-initialize the `CognitoUser` and `CognitoUserSession` objects from the stored token.
    *   **Files to Modify**: `fomomon/lib/main.dart`, `fomomon/lib/services/auth_service.dart`.

3.  **Defer Authentication to Point of Use**:
    *   The user can now create `CapturedSession`s entirely offline. The actual authentication (token refresh) is only required for network operations.
    *   When the user initiates an upload, `UploadService` will call `AuthService.getValidToken()`. At this point, `AuthService` will attempt to use the refresh token to get a new ID token from Cognito.
    *   If the refresh token has expired or is invalid, `getValidToken()` should throw a specific exception, such as `AuthSessionExpiredException`.

4.  **Handle Expired Session in UI**:
    *   The UI layer responsible for the upload action (likely in `HomeScreen` or a widget it contains) must catch the `AuthSessionExpiredException`.
    *   Upon catching this error, it should display a message to the user ("Your session has expired, please log in again") and navigate them to the `LoginScreen` to re-authenticate.
    *   **Files to Modify**: `fomomon/lib/screens/home_screen.dart` (or the upload widget), `fomomon/lib/services/upload_service.dart`.

---

## 2. Upload Queue Gallery and State Corruption

### Issue

The upload progress indicator is sometimes unreliable, showing an incorrect count of pending uploads (e.g., `0/2 uploaded` when all are complete). This suggests local state corruption or that the state is not being re-evaluated correctly. Furthermore, users have no way to view, manage, or delete sessions that are pending upload, leading to a black box experience.

### Proposed Fix

Replace the existing online map view with a gallery of un-uploaded sessions. This provides transparency and manual control over the upload queue.

1.  **Create the Upload Queue Screen**:
    *   Repurpose `online_map_screen.dart`. Rename the file and class to `upload_queue_screen.dart` and `UploadQueueScreen`.
    *   Remove the `FlutterMap` widget and its related logic.
    *   The primary widget on this screen will now be a new "Upload Queue Gallery".

2.  **Implement the Upload Queue Gallery**:
    *   This gallery will be a scrollable list. Its state should be driven by a fresh call to `LocalSessionStorage.loadAllSessions()` that is filtered to only show sessions where `isUploaded` is `false`.
    *   Each item in the list will be a card representing one `CapturedSession`.
    *   The card should display a thumbnail of the portrait image, the `siteId`, and the capture `timestamp`.
    *   **Files to Modify**: `fomomon/lib/screens/upload_queue_screen.dart`. A new widget `upload_gallery_item.dart` should be created.

3.  **Implement Session Detail and Discard Dialog**:
    *   When a user taps on a gallery card, a modal dialog should appear.
    *   This dialog must display:
        *   A larger preview of both the portrait and landscape images.
        *   The survey responses from the session.
    *   The dialog must have two buttons: "Keep" (which closes the dialog) and "Delete".
    *   **Files to Modify**: A new dialog widget should be created.

4.  **Implement Discard Functionality**:
    *   The "Discard" button will permanently delete the selected session and its associated data.
    *   Create a new method in `LocalSessionStorage`, e.g., `deleteSession(String sessionId)`.
    *   This method must delete the session's JSON file from local storage and also delete the associated portrait and landscape image files from the device.
    *   After deletion, the gallery UI must refresh to remove the discarded item.
    *   **Files to Modify**: `fomomon/lib/services/local_session_storage.dart`.

5.  **Fix Upload Progress Indicator**:
    *   Ensure the upload progress indicator widget (widgets.UploadDialWidget) also gets its state from a fresh call to `LocalSessionStorage.loadAllSessions().where((s) => !s.isUploaded)`, guaranteeing it always shows the correct count.
    * Even when the new Discard logic fires to delete a session, it should reflect in an updated upload count. 
    *   **Files to Modify**: UploadDialWidget used in the `online_map_screen.dart` screen
