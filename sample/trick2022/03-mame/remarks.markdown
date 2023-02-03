Execute the program normally.

```
$ ruby entry.rb
```

It shakes a string.

... Wait! This is not all.

Next, please apply "leftward gravity" to each letter in the file.
IOW, if there is a space to the left of a letter, move it to the left.
Here, you may want to use the following command.

```
$ sed "s/ //g" entry.rb | tee up.rb
```

This program applies "upward gravity" to each letter in an input text.
The following demo will help you understand what this means.

```
$ cat test.txt
$ ruby up.rb test.txt
```

Now, here's where we come in.
Please apply "upward gravity" to entry.rb.

```
$ ruby up.rb entry.rb | tee left.rb
```

I think that you already noticed that.
This program applies "leftward gravity" to an input text.

```
$ cat test.txt
$ ruby left.rb test.txt
```

`sed` is no longer required to create `up.rb`; just use `left.rb`.

```
$ ruby left.rb entry.rb > up.rb
```

We've come to the final stage.
Please apply `left.rb` to `left.rb`.

```
$ ruby left.rb left.rb | tee horizontal.rb
$ ruby horizontal.rb
```

Of course, it is also possible to apply `up.rb` to `up.rb`.

```
$ ruby up.rb up.rb | tee vertical.rb
$ ruby vertical.rb
```

Can you tell how they work? Enjoy analyzing!



---
Code reading tips (spoiler)

Some code fragments are highly reused between the programs.
For example, note that this program has one code fragment to input a text
(`b=$>.read`); `up.rb` and `left.rb` share and use this code fragment.
Also, `horizontal.rb` and `vertical.rb` share the fragment `puts'TRICK+2022'`.
Sometimes letters in very distant places are reused all over the place.

Can you tell how it detects if it is already aligned or not yet?
Here is a simplified version of the gimmick to switch behavior when
left-aligned:

```
"\ #{puts('not left-aligned yet')}
   # {puts('left-aligned')}"
```

And for top-aligned:

```
"#
xx{puts('top-aligned')}
x#{puts('not top-aligned yet')}
"
```

It is also necessary to detect "top-left-aligned" and "left-top-aligned".
I made tons of subtle adjustments and trial-and-error to create the program.
I no longer know precisely how it works.
