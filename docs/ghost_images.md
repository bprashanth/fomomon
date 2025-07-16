# Ghost image overlays 

Goal: 
1. Track changes in sky, understory, ground
2. Capture a _comparable field of view_ across time 

The problem, stated simply, is to guide the user to a single spot along the x, y and z dimensions, and have them take a picture repeatedly over time. For the x and y dimensions we use gps and for the z, we use compass. BUT, due to battery, accuracy and other real world constraints, this doesn't always work well. 

So a stand in replacement is to provide a "ghost image" overlay, and arrange some stones on the ground. The user can still use technology to reach a point, roughly speaking, but then they have to look around for the stone on the ground. Then they ask another human to stand at a second stone on the ground, line up the humans, and shoot. 

In other words, the ghost image is an assist for fine tuning the z coordinate. The stones are an assistance for fine tuning the x, y coordinates. One problem with this approach, as described in the next section, is that different phones scale images differently. While we can use certain anchor points to scale the image accurately, in some cases, the "game" of lining up humans might distract the user from the real goal - which is to take the same picture everytime. 

An alternate solution is to only use the ghost image as a brief assist. Not to line up the human at all, but once the landscape is confirmed, to then line up
1. the bottom third line with the ground (which, presumably, doesn't grow)
2. a crosshair in the middle of the screen with the humans head

If 2 stones are used, and the cross hair lines up, we capture the x, y and z without distracting the user (?).

## The problem with ghost images 

A few potential issues with ghost images, from a ux perspective:     
1. Visual clutter. 
2. It distracts the user with a line-em-up game. 
3. To use the ghost properly, we must avoid stretching the image _non-uniformly_ on different phones. Eg: 

> A 100×100 image shown on a 200×200 screen: each pixel becomes 2×2: alignment preserved.

> A 100×100 image shown on a 200×100 screen: only x gets stretched: misalignment.

The ideal algorithm to make an image "fit" is to scale uniformly. When we scale non-uniformly, pixels get interpolated or discarded. But this uniform scaling is not always up to us, as the following examples show. 

There are 2 common ways to deal with this: 
1. The most common algorithm for box fitting (`BoxFit.contain`) could result in cropping or letterboxing - and when this happens, if the user is playing the line-em-up game, they will take plants to the left or right instead. 
2. The second way, is to use `BoxFit.cover`. This will expand or shrink the image but keep the center rougly in the center. Again, this could lead to user confusion if they're playing line-em-up, because the human will be bigger or smaller than the real human. 

#### Case 1: BoxFit working 
```
Image: 100px wide × 200px tall
Screen: 200px wide × 400px tall
Person's head: 1/2 image width, 2/3 image height = 50px, 133px
Desired location of head: 1/2 screen width, 2/3 screen height = 100px, 266px
```
1. Scale factor: 
	x: 200/100: 2.0
	y: 400/200: 2.0
2. Minimum scale factor: 2.0
3. Scale: 100`*`scale factor x 200`*`scale factor = 200x400 
	- vertical left over space: 0
	- horizontal left over space: 0
4. Offset: none needed
	- head in image after scaling: (100px, 266px)

#### Case 2: BoxFit fails 
```
Image: 100px wide × 200px tall
Screen: 300px wide × 800px tall
Person's head: 1/2 image width, 2/3 image height = 50px, 133px
Desired location of head: 1/2 screen width, 2/3 screen height = 150px, 533px
```
1. Scale factor: 
	x: 300/100: 3.0
	y: 800/200: 4.0
2. Minimum scale factor: 3.0
3. Scale: 100`*`3.0 x 200`*`3.0 = 300x600
	- vertical left over space: 200px 
	- horizontal left over space: 0
4. Offset: 200 needed on y
	- default behavior, apply 100px on left 100px on right
	- head in image after scaling: (150, 399)
	- head in image after default offset: (150, 499)

This is problematic because 
1. It fits the whole image in the screen
2. But we don't care about fittin the whole image in the screen

We want to have the person in the ghost line up with the person irl. 
A 200px x 200px human needs to show up as a 200px x 200px human on all screens. 
If this happens, regardless of the sky and land fitting, and we line up the human with the irl human, we will capture the same fraction of sky and land. 


#### Case 3: Manual scaling (anchor point) 
```
Image: 100px wide × 200px tall
Screen: 300px wide × 800px tall
Person's head: 1/2 image width, 2/3 image height = 50px, 133px
Desired location of head: 1/2 screen width, 2/3 screen height = 150px, 533
```
1. Scale factor: 
	x: 300/100: 3.0
	y: 800/200: 4.0
2. Minimum scale factor: 3.0
3. Scale: 100`*`3.0 x 200`*`3.0 = 300x600
	- vertical left over space: 200px 
	- horizontal left over space: 0
4. Offset: 200 needed on y
	- non default offset of 134 (533-399)
	- head in image after scaling: (150, 399)
	- head in image after offset: (150, 533)


