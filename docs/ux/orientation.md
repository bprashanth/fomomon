# Heading and orientation

This doc describes how the app decides “you’re facing the site” and the turn advisories (turn left / right / turn around), and a proposed improvement using a stored **reference heading** when you add a site.

---

## Current behavior: bearing vs heading

The advisory (e.g. “You’re facing the site”, “Turn around”, “Turn slightly right”) is computed in `lib/widgets/route_advisory.dart` using two angles:

1. **Heading** – From the device compass (FlutterCompass): the direction the phone is **pointing** relative to magnetic north (0–360°).
2. **Bearing** – From `Geolocator.bearingBetween(userLat, userLng, siteLat, siteLng)`: the **direction from the user’s position to the site** (i.e. “which way is the site from here?”).

The logic is: *you’re “facing the site” when the direction you’re pointing (heading) is close to the direction to the site (bearing)*.

- `diff = (bearing - heading)` normalized to ±180°.
- `diff.abs() < 15°` → “You’re facing the site”.
- Small `diff` → “Turn slightly left/right”; larger → “Turn left/right”; `diff` near ±180° → “Turn around”.

So with **only lat/long**, “facing the site” really means: **you’re pointing toward the site’s location**. That is correct when you are **at a distance**: the advisory answers “which way should I turn so I’m pointing at the site?”

---

## Why it goes wrong when you’re at the site

When you’re **at** (or very close to) the site, your position and the site’s position are the same or almost the same:

- **Bearing is undefined or unstable** when the two points coincide (distance ≈ 0). Different devices/libraries may return 0 or arbitrary values, and tiny GPS jitter can make bearing jump by large angles.
- So even when you’re **actually facing the spot** (e.g. looking at the tree you’re standing at), the app may see a bearing that doesn’t match your heading and show “Turn around” or other wrong advisories.

So: **with only lat/long, the app cannot reliably know “you’re facing the site” when you’re already at the site**, because “direction to the site” has no clear meaning there. What *would* be meaningful at the site is: “you’re facing the **same direction** the person who recorded the site was facing.”

---

## High-level behavior: two phases

The intended mental model:

1. **When you’re far from the site**  
   Use **bearing** (direction to the site) vs **heading** (where you’re pointing).  
   Advisories: turn left/right / turn around so you’re **pointing toward the site**.  
   (This is the current behavior and is correct at distance.)

2. **When you’re at (or very near) the site**  
   Use **reference heading** (direction the recorder was facing when they added the site) vs **heading** (where you’re pointing now), but this is now surfaced on the **capture screen**, not in the home advisory:
   - Home screen still answers “which way is the site from here?” (bearing vs heading).
   - The capture screen answers “how do I turn to match the original photo’s orientation?” (reference heading vs heading).

So:

- **Far:** “Face the **location**” → bearing vs heading.
- **At site:** “Face the **same way the site was recorded**” → reference heading vs heading.

That way “Turn around” at the site means “turn around so you match the recorded orientation,” not “point at the site” (which is already true when you’re on it).

---

## How we implement this

### 1. When adding a site

When the user creates a new local site (e.g. on the site selection screen, at the moment they confirm “create this site here”):

- Record the **current compass heading** at that moment.
- Store it as the site’s **reference heading** (e.g. `reference_heading` in the `Site` model and in `local_sites.json`).
- Optionally show a short confirmation: e.g. “You’re facing forward now; we’ll remember this orientation for the site.”

So “the site” is defined as: this lat/long **and** this viewing direction.

### 2. Data model

- Add an optional `reference_heading` (double, 0–360, or null) to `Site`.
- When creating a local site, set it from the compass at creation time.
- Persist it in `local_sites.json` and, if/when local sites are synced to remote, in the remote schema so future clients can use it too.

---

## How the UI uses this

### Home screen advisory (bearing-based)

On the home screen (`route_advisory.dart`), we intentionally keep the logic **purely bearing-based**:

- Input: user position, site position, compass heading.
- Output: “You’re facing the site”, “Turn slightly right/left”, “Turn right/left”, “Turn around”, “Head N/NE/…”.

This advisory always answers: **“which way should I turn so I’m pointing toward the site’s location?”** It does **not** try to capture how the reference image was framed.

### Capture screen: “Turn to match” dial

On the **first portrait capture** (`CaptureScreen`):

- If the selected `Site` has a `referenceHeading`, we:
  - Start a compass stream (`FlutterCompass`) to track live heading.
  - Render an `OrientationDial` widget under the site ID:
    - Top marker = reference heading (how the original reference image was taken).
    - Moving marker = current heading.
    - When they line up (within ≈15°), both the ring and markers turn green.
  - Show a small label: **“Turn to match”**.

Semantics:

- This dial is about **turning around the site (yaw)**, not tilting up/down.
- It helps the user roughly re-create the same framing as the reference image when they are at the site.

On web/PWA we typically don’t have reliable compass data; in that case the heading is treated as null and the `OrientationDial` does not render, so the capture UI behaves as before.

---

## Summary

| Situation | What we use | What the UI tells the user |
|-----------|-------------|----------------------------|
| **Far from site** | Bearing (user → site) vs heading | Home advisory: “Turn left/right / Turn around / Head N/NE/…” so you point **toward** the site. |
| **At site, with reference heading** | Reference heading vs heading | Capture screen: circular dial + “Turn to match” so you turn **the same way** the site was originally recorded. |

With **only lat/long**, we can’t know the intended viewing direction at the site. Storing a **reference heading** when the site is added, and using it in the capture screen’s orientation dial, fixes that: the user can now both get to the site (bearing) and then turn to match the original shot (reference heading) without overloading the home advisory. 
