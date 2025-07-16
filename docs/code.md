## Code philosophies 

* Talking to the outside world happens through a service 
	- These typically involve "outside app" logic, like I/O
	- Network calls 
	- local storage 
	- Device APIs
* Pure logic helpers are "utils" 
	- These are typically stateless and synchronous
	- string formatting
	- id generation 
	- json serialization
	- sanitization
* Models
	- Data structures for storage 
* Widgets 
	- UI helpers (styling etc) 
* Lib is the apps root namespace, avoid putting things here
	- Entrypoints like main.dart and app.dart 

Sample code layout 
```console
lib/
├── main.dart
├── app.dart                      # App scaffold & MaterialApp
├── theme/                        # Custom colors/fonts later
│   └── app_theme.dart
├── models/
│   ├── user.dart
│   ├── site.dart
│   ├── captured_session.dart
├── services/
│   ├── gps_service.dart
│   ├── site_service.dart
│   ├── user_service.dart
│   ├── upload_service.dart
│   └── hive_storage.dart
├── screens/
│   ├── login_screen.dart
│   ├── home_screen.dart
│   ├── capture_screen.dart
│   ├── confirm_screen.dart
│   ├── survey_screen.dart
│   └── gallery_screen.dart
├── widgets/
│   ├── feedback_ring.dart
│   ├── session_card.dart
│   └── big_plus_button.dart
```
