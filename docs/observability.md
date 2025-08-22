# Observability 

This doc has a brief overview of the desired observability metrics. 
The current version of the app only uses print statements.

## Current Issues with logging 

What we want - remote telemetry
What we have - print statements
Print statements tend to stay on the phone

1. Crash reporting 
2. Event logging (lightweight analytics) 
3. Log statements that compile out at build time 
...

Firebase free tier will get you 1 and 2. This will allow us to 
1. Crashlytics: uncaught exceptions, stack traces etc
2. Analytics: log key actions under keys, eg `gps_fix_failed` and `login`. 

For 3, we should switch to using `kDebugMode`
```
import 'package:flutter/foundation.dart';

if (kDebugMode) {
  print('Debug-only log');
}
```
OR move to a more centralized logging utility. 

### Crashes

By default flutter/android won't send crash data anywhere. The philosophy we went with is 
	a. Internal testing: not mandatory. Trust your testers to give feedback.
	b. Production: Essential. Even if we don't plan to analyze them, having them around is extremely useful. 

Seeing trends in eg increased crashes is extremely useful. 
Crash reports also help in catching hiesenbugs. 


