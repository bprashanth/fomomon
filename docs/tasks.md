
## Completed 

* Login screen with org, name, email
* Configurable bucketRoot templated via org and app name
* Sites and users fetched via `site_service` 
* GPS permission and streaming via `gps_service`
* Visual feedback on HomeScreen with site/user dots`*`
* Mocking infrastructure for offline testing
* Modular structure for services and screens

## In Progress / Pending Fixes

* Fix GpsFeedbackPanel
	- Make user dot dynamic (based on GPS)
	- Style site/user dots as circles

## Site Entry (0.5 days)

* Add a large "+" when near a site 
* Tapping it launches the pipeline

## Capture pipeline (2 days)

1. Step 1: Landscape photo with ghost overla
2. Step 2: Portrait photo with ghost overlay
3. Step 3: Survey questions from site config
4. Step 4: Save local session (JSON + image paths)

## Local Session (1 day)

Via hive

* Use unique IDs for session files
* Keep files in db/ directory until upload
* Include metadata: site_id, timestamp, user info, etc.

## Upload Logic (1 day)

* Upload button on Home or Upload screen
* Only delete session after full upload succeeds

## Sync and Refresh (0.5 day)

* Poll sites.json and suers.json daily

