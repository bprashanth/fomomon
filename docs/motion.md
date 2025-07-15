## Motion feedback 

### Mock

The location tracker is more like a mini radar or proximity map, not a geographic map. Why? because storing a map offline is heavy and unnecessary and more complex than we need it to be. Instead our users largely know where they are going, sometimes they just need a nudge in the right direction, and they need to know where the "stone" on the ground is. When they are 10m from it, the plus button lights up. 

```
[Text: “Nearby sites”]
+-----------------------+
|        +              |  ← upcoming site dot
|                       |
|           -           |  ← user’s position (centered)
|                       |
|                       +  ← other site (on outer fringe)
+-----------------------+
```

In other words, the user dot stays at the center of the screen. The sites move inwards from the border as the user moves closer to them. 


### How this works 

* We use a fixed size container (200x200) to simulate a map
* This is a 2d plane centered on user 
* Place all site dots that fit in this 200px relative to user (i.e this gives us a 360m radius)
* Sites outside the 360m radius are dots on the map edge
* This requires a transformation from gps->2d offsets
* When distance < threshold, draw a glow/ring
* Always draw a "you are here" dot in the center
* If any site is in range, highlight big "+" button 




