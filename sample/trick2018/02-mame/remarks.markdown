This program quines with animation.

```
$ ruby entry.rb
```

Of course, the output is executable.

```
$ ruby entry.rb > output
$ ruby output
```

Note, we don't cheat.  This program uses escape sequences just for moving the cursor.  It doesn't use attribution change nor overwrite to hide any code.

The program is crafted so that it works in two ways; it works as a normal program text, and, it also works when it is rearranged in a spiral order.  Some parts of the code are actually overlapped.
