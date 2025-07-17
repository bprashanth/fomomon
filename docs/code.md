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

## Best Practices 

### Dead widgets 

Use `if (!mounted) return` before 
	- `setState()`
	- `Navigator.of(context)...`
	- async calls

General pattern 
```
await anythingAsync();
if (!mounted) return;  // Always do this before UI updates
```
If the user has navigated away from that widget, you want to avoid say, triggering a Navigation to some unrelated screen. 


### Re-entry into a widget 

Reentry into a widget can happen in 2 main ways 
1. On `pop`, this happens when the user hits "retake" on the confirmation screen, which puts them back into the capture screen
2. On explicit invocation. This happen when the user goes through the pipeline naturally, the same confirm screen and capture screens are invoked one after the other. 

2 things we need to keep in mind: 
1. State: As we go through the pipeline, the capture screen itself is aware of some "state", in this case `args.captureMode`. When this is set to "portrait" it does 3 things: 
	- Ensure the screen orientation is indeed portrait, this happens through `init`
	- Ensure the right "portrait" ghost image is used 
	- Ensure the image captured is stored in the right fields of the `ConfirmScreenArgs`

2. Preconditions: When we "pop" back into the capture screen, it might be making certain assumptions about its own state. Specifically, orientation might have changed. If the subsequent screen modifies such conditions, it must reset them before poping back. In this case, we reset the orientation in `onRetake`. 
	- This is preferable because we know we need to reset portrait mode orientation, and doing so in the capture screen `init` is more deterministic than doing so from teh capture screen `dispose`. Dispose is not immediately called on entry into a new screen.  
