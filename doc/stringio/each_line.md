With a block given calls the block with each remaining line (see "Position" below) in the stream;
returns `self`.

Leaves stream position at end-of-stream.

**No Arguments**

With no arguments given,
reads lines using the default record separator
(global variable `$/`, whose initial value is `"\n"`).

```ruby
strio = StringIO.new(TEXT)
strio.each_line {|line| p line }
strio.eof? # => true
```

Output:

```
"First line\n"
"Second line\n"
"\n"
"Fourth line\n"
"Fifth line\n"
```

**Argument `sep`**

With only string argument `sep` given,
reads lines using that string as the record separator:

```ruby
strio = StringIO.new(TEXT)
strio.each_line(' ') {|line| p line }
```

Output:

```
"First "
"line\nSecond "
"line\n\nFourth "
"line\nFifth "
"line\n"
```

**Argument `limit`**

With only integer argument `limit` given,
reads lines using the default record separator;
also limits the size (in characters) of each line to the given limit:

```ruby
strio = StringIO.new(TEXT)
strio.each_line(10) {|line| p line }
```

Output:

```
"First line"
"\n"
"Second lin"
"e\n"
"\n"
"Fourth lin"
"e\n"
"Fifth line"
"\n"
```

**Arguments `sep` and `limit`**

With arguments `sep` and `limit` both given,
honors both:

```ruby
strio = StringIO.new(TEXT)
strio.each_line(' ', 10) {|line| p line }
```

Output:

```
"First "
"line\nSecon"
"d "
"line\n\nFour"
"th "
"line\nFifth"
" "
"line\n"
```

**Position**

As stated above, method `each` _remaining_ line in the stream.

In the examples above each `strio` object starts with its position at beginning-of-stream;
but in other cases the position may be anywhere (see StringIO#pos):

```ruby
strio = StringIO.new(TEXT)
strio.pos = 30 # Set stream position to character 30.
strio.each_line {|line| p line }
```

Output:

```
" line\n"
"Fifth line\n"
```

In all the examples above, the stream position is at the beginning of a character;
in other cases, that need not be so:

```ruby
s = 'こんにちは'  # Five 3-byte characters.
strio = StringIO.new(s)
strio.pos = 3   # At beginning of second character.
strio.each_line {|line| p line }
strio.pos = 4   # At second byte of second character.
strio.each_line {|line| p line }
strio.pos = 5   # At third byte of second character.
strio.each_line {|line| p line }
```

Output:

```
"んにちは"
"\x82\x93にちは"
"\x93にちは"
```

**Special Record Separators**

Like some methods in class `IO`, StringIO.each honors two special record separators;
see {Special Line Separators}[https://docs.ruby-lang.org/en/master/IO.html#class-IO-label-Special+Line+Separator+Values].

```ruby
strio = StringIO.new(TEXT)
strio.each_line('') {|line| p line } # Read as paragraphs (separated by blank lines).
```

Output:

```
"First line\nSecond line\n\n"
"Fourth line\nFifth line\n"
```

```ruby
strio = StringIO.new(TEXT)
strio.each_line(nil) {|line| p line } # "Slurp"; read it all.
```

Output:

```
"First line\nSecond line\n\nFourth line\nFifth line\n"
```

**Keyword Argument `chomp`**

With keyword argument `chomp` given as `true` (the default is `false`),
removes trailing newline (if any) from each line:

```ruby
strio = StringIO.new(TEXT)
strio.each_line(chomp: true) {|line| p line }
```

Output:

```
"First line"
"Second line"
""
"Fourth line"
"Fifth line"
```

With no block given, returns a new {Enumerator}[https://docs.ruby-lang.org/en/master/Enumerator.html].


Related: StringIO.each_byte, StringIO.each_char, StringIO.each_codepoint.
