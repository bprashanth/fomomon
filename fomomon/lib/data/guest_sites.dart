/// guest_sites.dart
/// ----------------
/// Contains hardcoded guest sites data for offline/demo mode.
///
/// Guest mode is enabled when the user taps "Continue as Guest" on the login
/// screen. In this mode:
/// - `AppConfig.configureGuestMode()` is called, setting `isGuestMode = true`.
/// - `SiteService.fetchSitesAndPrefetchImages()` detects guest mode and calls
///   `_loadGuestSites()` instead of fetching `sites.json` from the network.
/// - `_loadGuestSites()` parses this JSON string and uses the `bucket_root`
///   field (`https://fomomonguest.s3.ap-south-1.amazonaws.com/`) as the
///   bucket root for all guest sites.
/// - Uploads in guest mode still go through `UploadService`, but because
///   no Cognito login ever happens, `AuthService.isUserLoggedIn()` is false
///   and the app always uses the *no-auth* upload path
///   (`_uploadFileNoAuth` / `_uploadJsonNoAuth`) directly to this public bucket.
/// - This means guest uploads never use Cognito tokens or `getValidToken()`,
///   and the new AuthSessionExpiredException-based login redirect logic
///   does not affect guest mode.

class GuestSites {
  static const String guestSitesJson = '''
{
  "bucket_root": "https://fomomonguest.s3.ap-south-1.amazonaws.com/",
  "sites": [
    {
      "id": "H13R1",
      "location": {
        "lat": 10.31329,
        "lng": 76.83704
      },
      "reference_portrait": "H13R1_2025-03-DSCN2990.JPG",
      "reference_landscape": "H13R1_2025-03-DSCN2990.JPG",
      "local_portrait_path": "assets/images/guest_sites/H13R1_2025-03-DSCN2990.JPG",
      "local_landscape_path": "assets/images/guest_sites/H13R1_2025-03-DSCN2990.JPG",
      "survey": [
        {
          "id": "q1",
          "question": "What animals did you see?",
          "type": "text"
        },
        {
          "id": "q2",
          "question": "Was there litter?",
          "type": "mcq",
          "options": [
            "Yes",
            "No"
          ]
        }
      ]
    },
    {
      "id": "J12R1",
      "location": {
        "lat": 10.31284,
        "lng": 76.83536
      },
      "reference_portrait": "J12R1_2025-03-DSCN2975.JPG",
      "reference_landscape": "J12R1_2025-03-DSCN2975.JPG",
      "local_portrait_path": "assets/images/guest_sites/J12R1_2025-03-DSCN2975.JPG",
      "local_landscape_path": "assets/images/guest_sites/J12R1_2025-03-DSCN2975.JPG",
      "survey": [
        {
          "id": "q1",
          "question": "What animals did you see?",
          "type": "text"
        },
        {
          "id": "q2",
          "question": "Was there litter?",
          "type": "mcq",
          "options": [
            "Yes",
            "No"
          ]
        }
      ]
    },
    {
      "id": "P1R1",
      "location": {
        "lat": 10.30987,
        "lng": 76.83476
      },
      "reference_portrait": "P1R1_2019-09-DSCN8514.JPG",
      "reference_landscape": "P1R1_2019-09-DSCN8514.JPG",
      "local_portrait_path": "assets/images/guest_sites/P1R1_2019-09-DSCN8514.JPG",
      "local_landscape_path": "assets/images/guest_sites/P1R1_2019-09-DSCN8514.JPG",
      "survey": [
        {
          "id": "q1",
          "question": "What animals did you see?",
          "type": "text"
        },
        {
          "id": "q2",
          "question": "Was there litter?",
          "type": "mcq",
          "options": [
            "Yes",
            "No"
          ]
        }
      ]
    },
    {
      "id": "P1R2",
      "location": {
        "lat": 10.31025,
        "lng": 76.83468
      },
      "reference_portrait": "P1R2_2019-11-DSCN8523.JPG",
      "reference_landscape": "P1R2_2019-11-DSCN8523.JPG",
      "local_portrait_path": "assets/images/guest_sites/P1R2_2019-11-DSCN8523.JPG",
      "local_landscape_path": "assets/images/guest_sites/P1R2_2019-11-DSCN8523.JPG",
      "survey": [
        {
          "id": "q1",
          "question": "What animals did you see?",
          "type": "text"
        },
        {
          "id": "q2",
          "question": "Was there litter?",
          "type": "mcq",
          "options": [
            "Yes",
            "No"
          ]
        }
      ]
    },
    {
      "id": "P2R1",
      "location": {
        "lat": 10.30991,
        "lng": 76.83501
      },
      "reference_portrait": "P2R1_2019-11-DSCN8516.JPG",
      "reference_landscape": "P2R1_2019-11-DSCN8516.JPG",
      "local_portrait_path": "assets/images/guest_sites/P2R1_2019-11-DSCN8516.JPG",
      "local_landscape_path": "assets/images/guest_sites/P2R1_2019-11-DSCN8516.JPG",
      "survey": [
        {
          "id": "q1",
          "question": "What animals did you see?",
          "type": "text"
        },
        {
          "id": "q2",
          "question": "Was there litter?",
          "type": "mcq",
          "options": [
            "Yes",
            "No"
          ]
        }
      ]
    },
    {
      "id": "P2R2",
      "location": {
        "lat": 10.30926,
        "lng": 76.83543
      },
      "reference_portrait": "P2R2_2022-09-DSCN7780.JPG",
      "reference_landscape": "P2R2_2022-09-DSCN7780.JPG",
      "local_portrait_path": "assets/images/guest_sites/P2R2_2022-09-DSCN7780.JPG",
      "local_landscape_path": "assets/images/guest_sites/P2R2_2022-09-DSCN7780.JPG",
      "survey": [
        {
          "id": "q1",
          "question": "What animals did you see?",
          "type": "text"
        },
        {
          "id": "q2",
          "question": "Was there litter?",
          "type": "mcq",
          "options": [
            "Yes",
            "No"
          ]
        }
      ]
    }
  ]
}
''';
}
