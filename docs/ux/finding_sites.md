# Finding Sites (Orientation & Guidance)

## Goal
Guide a user in the field to align their view with a target site using a
light cone + site dots + route advisory text.

## Two Orientation Modes

### North-up (world-fixed)
- Screen "up" is always North.
- N/E/S/W labels are fixed and do not rotate.
- Site dots are plotted by true bearing (north-referenced) and stay fixed.
- The light cone rotates with the user's heading.
- Interpretation: the world is fixed; your orientation indicator moves.

### Heading-up (user-fixed)
- Screen "up" is always the direction the user is facing.
- The light cone is fixed, pointing up.
- N/E/S/W labels rotate with heading (world rotates under you).
- Site dots rotate with the labels (world-fixed relative to N/E/S/W).
- Interpretation: turn until the site dot is inside the light cone.

## Current Behavior: Heading-up
We use **heading-up** to minimize cognitive load in the field.
- The light cone is fixed straight up.
- Site dots and N/E/S/W labels rotate together as heading changes.
- When the route advisory says "Turn right/left," the dots should move toward
  the cone in the expected direction, and the correct site should enter the
  cone when the user faces it.

## Alignment With Advisory
The route advisory uses the signed difference between bearing and heading.
When the advisory says "You're facing the site," the site dot should appear
inside the cone (within its sweep).

When the user is very close to the site, bearing becomes noisy and can flip
rapidly. To avoid misleading turn instructions at close range, the advisory
switches to a proximity message ("You are near the site") within a configurable
distance threshold.

## Notes
- Heading is sourced from device compass when available.
- On platforms without reliable compass (e.g. some PWA browsers), the cone and
  rotation may be unavailable or degraded; the UI should handle this state.
