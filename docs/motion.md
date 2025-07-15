## Motion feedback 

### Mock
```
[Text: “Nearby sites”]
+-----------------------+
|        +              |  ← glowing site dot
|                       |
|           -           |  ← user’s position (centered)
|                       |
|             \         |  ← other site
+-----------------------+
```


### How this works 

* We use a fixed size container (200x200) to simulate a map
* This is a 2d plane centered on user 
* Place all site dots that fit in this 200px relative to user (i.e this gives us a 360m radius)
* Sites outside the 360m radius are dots on the map edge
* This requires a transformation from gps->2d offsets
* When distance < threshold, draw a glow/ring
* Always draw a "you are here" dot in the center
* If any site is in range, highlight big "+" button 




