### Remarks

1. Run it with `ruby entry.rb 8080`

2. Open "http://localhost:8080"

3. Click on the screen and interact with it

I confirmed the following implementations/platforms:

* Ruby Version
  * ruby 3.1.0p0 (2021-12-25 revision fb4df44d16) [x86_64-darwin20]
* Browser
  * Chrome(macOS, Android)
  * Firefox(macOS)
  * Edge(macOS)

### Description

This program is an HTTP server that provides a fractal creature playground.
You can see the heartbeat of a mysterious fractal creature. Clicking on the screen will change the shape of the creature.
Surprisingly, this interactive webpage is built without JavaScript.

### Internals

Fractal: Iterated function system
Rendering from server: Streaming animated GIF
Sending click event to server: `<input type="image" src="streaming.gif">` with `<form target="invisible_iframe">`

### Limitations

Does not work on Safari and iOS.
