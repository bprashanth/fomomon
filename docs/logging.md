## Issues with logging 

What we want - remote telemetry
What we have - print statements
Print statements tend to stay on the phone

1. Crash reporting 
2. Event logging (lightweight analytics) 
...

Firebase free tier will get you 1 and 2. This will allow us to 
1. Crashlytics: uncaught exceptions, stack traces etc
2. Analytics: log key actions under keys, eg `gps_fix_failed` and `login`. 
