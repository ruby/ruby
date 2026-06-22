\Class \StringIO supports accessing a string as a stream,
similar in some ways to [class IO][io class].

You can create a \StringIO instance using:

- StringIO.new: returns a new \StringIO object containing the given string.
- StringIO.open: passes a new \StringIO object to the given block.

Like an \IO stream, a \StringIO stream has certain properties:

- **Read/write mode**: whether the stream may be read, written, appended to, etc.;
  see [Read/Write Mode][read/write mode].
- **Data mode**: text-only or binary;
  see [Data Mode][data mode].
- **Encodings**: internal and external encodings;
  see [Encodings][encodings].
- **Position**: where in the stream the next read or write is to occur;
  see [Position][position].
- **Line number**: a special, line-oriented, "position" (different from the position mentioned above);
  see [Line Number][line number].
- **Open/closed**: whether the stream is open or closed, for reading or writing.
  see [Open/Closed Streams][open/closed streams].
- **BOM**: byte mark order;
  see [Byte Order Mark][bom (byte order mark)].

## About the Examples

Examples on this page assume that \StringIO has been required:

```ruby
require 'stringio'
```

And that this constant has been defined:

```ruby
TEXT = <<EOT
First line
Second line

Fourth line
Fifth line
EOT
```

## Stream Properties

### Read/Write Mode

#### Summary

|            Mode            | Initial Clear? |   Read   |  Write   |
|:--------------------------:|:--------------:|:--------:|:--------:|
|  <tt>'r'</tt>: read-only   |       No       | Anywhere |  Error   |
|  <tt>'w'</tt>: write-only  |      Yes       |  Error   | Anywhere |
| <tt>'a'</tt>: append-only  |       No       |  Error   | End only |
| <tt>'r+'</tt>: read/write  |       No       | Anywhere | Anywhere |
| <tt>'w+'</tt>: read-write  |      Yes       | Anywhere | Anywhere |
| <tt>'a+'</tt>: read/append |       No       | Anywhere | End only |

Each section below describes a read/write mode.

Any of the modes may be given as a string or as file constants;
example:

```ruby
strio = StringIO.new('foo', 'a')
strio = StringIO.new('foo', File::WRONLY | File::APPEND)
```

#### `'r'`: Read-Only

Mode specified as one of:

- String: `'r'`.
- Constant: `File::RDONLY`.

Initial state:

```ruby
strio = StringIO.new('foobarbaz', 'r')
strio.pos    # => 0            # Beginning-of-stream.
strio.string # => "foobarbaz"  # Not cleared.
```

May be read anywhere:

```ruby
strio.gets(3) # => "foo"
strio.gets(3) # => "bar"
strio.pos = 9
strio.gets(3) # => nil
```

May not be written:

```ruby
strio.write('foo')  # Raises IOError: not opened for writing
```

#### `'w'`: Write-Only

Mode specified as one of:

- String: `'w'`.
- Constant: `File::WRONLY`.

Initial state:

```ruby
strio = StringIO.new('foo', 'w')
strio.pos    # => 0   # Beginning of stream.
strio.string # => ""  # Initially cleared.
```

May be written anywhere (even past end-of-stream):

```ruby
strio.write('foobar')
strio.string # => "foobar"
strio.rewind
strio.write('FOO')
strio.string # => "FOObar"
strio.pos = 3
strio.write('BAR')
strio.string # => "FOOBAR"
strio.pos = 9
strio.write('baz')
strio.string # => "FOOBAR\u0000\u0000\u0000baz"  # Null-padded.
```

May not be read:

```ruby
strio.read  # Raises IOError: not opened for reading
```

#### `'a'`: Append-Only

Mode specified as one of:

- String: `'a'`.
- Constant: `File::WRONLY | File::APPEND`.

Initial state:

```ruby
strio = StringIO.new('foo', 'a')
strio.pos    # => 0      # Beginning-of-stream.
strio.string # => "foo"  # Not cleared.
```

May be written only at the end; position does not affect writing:

```ruby
strio.write('bar')
strio.string # => "foobar"
strio.write('baz')
strio.string # => "foobarbaz"
strio.pos = 400
strio.write('bat')
strio.string # => "foobarbazbat"
```

May not be read:

```ruby
strio.gets  # Raises IOError: not opened for reading
```

#### `'r+'`: Read/Write

Mode specified as one of:

- String: `'r+'`.
- Constant: `File::RDRW`.

Initial state:

```ruby
strio = StringIO.new('foobar', 'r+')
strio.pos    # => 0         # Beginning-of-stream.
strio.string # => "foobar"  # Not cleared.
```

May be written anywhere (even past end-of-stream):

```ruby
strio.write('FOO')
strio.string # => "FOObar"
strio.write('BAR')
strio.string # => "FOOBAR"
strio.write('BAZ')
strio.string # => "FOOBARBAZ"
strio.pos = 12
strio.write('BAT')
strio.string # => "FOOBARBAZ\u0000\u0000\u0000BAT"  # Null padded.
```

May be read anywhere:

```ruby
strio.pos = 0
strio.gets(3) # => "FOO"
strio.pos = 6
strio.gets(3) # => "BAZ"
strio.pos = 400
strio.gets(3) # => nil
```

#### `'w+'`: Read/Write (Initially Clear)

Mode specified as one of:

- String: `'w+'`.
- Constant: `File::RDWR | File::TRUNC`.

Initial state:

```ruby
strio = StringIO.new('foo', 'w+')
strio.pos    # => 0   # Beginning-of-stream.
strio.string # => ""  # Truncated.
```

May be written anywhere (even past end-of-stream):

```ruby
strio.write('foobar')
strio.string # => "foobar"
strio.rewind
strio.write('FOO')
strio.string # => "FOObar"
strio.write('BAR')
strio.string # => "FOOBAR"
strio.write('BAZ')
strio.string # => "FOOBARBAZ"
strio.pos = 12
strio.write('BAT')
strio.string # => "FOOBARBAZ\u0000\u0000\u0000BAT"  # Null-padded.
```

May be read anywhere:

```ruby
strio.rewind
strio.gets(3) # => "FOO"
strio.gets(3) # => "BAR"
strio.pos = 12
strio.gets(3) # => "BAT"
strio.pos = 400
strio.gets(3) # => nil
```

#### `'a+'`: Read/Append

Mode specified as one of:

- String: `'a+'`.
- Constant: `File::RDWR | File::APPEND`.

Initial state:

```ruby
strio = StringIO.new('foo', 'a+')
strio.pos    # => 0      # Beginning-of-stream.
strio.string # => "foo"  # Not cleared.
```

May be written only at the end; #rewind; position does not affect writing:

```ruby
strio.write('bar')
strio.string # => "foobar"
strio.write('baz')
strio.string # => "foobarbaz"
strio.pos = 400
strio.write('bat')
strio.string # => "foobarbazbat"
```

May be read anywhere:

```ruby
strio.rewind
strio.gets(3) # => "foo"
strio.gets(3) # => "bar"
strio.pos = 9
strio.gets(3) # => "bat"
strio.pos = 400
strio.gets(3) # => nil
```

### Data Mode

To specify whether the stream is to be treated as text or as binary data,
either of the following may be suffixed to any of the string read/write modes above:

- `'t'`: Text;
  initializes the encoding as Encoding::UTF_8.
- `'b'`: Binary;
  initializes the encoding as Encoding::ASCII_8BIT.

If neither is given, the stream defaults to text data.

Examples:

```ruby
strio = StringIO.new('foo', 'rt')
strio.external_encoding # => #<Encoding:UTF-8>
data = "\u9990\u9991\u9992\u9993\u9994"
strio = StringIO.new(data, 'rb')
strio.external_encoding # => #<Encoding:BINARY (ASCII-8BIT)>
```

When the data mode is specified, the read/write mode may not be omitted:

```ruby
StringIO.new(data, 'b')  # Raises ArgumentError: invalid access mode b
```

A text stream may be changed to binary by calling instance method #binmode;
a binary stream may not be changed to text.

### Encodings

A stream has an encoding; see [Encodings][encodings document].

The initial encoding for a new or re-opened stream depends on its [data mode][data mode]:

- Text: `Encoding::UTF_8`.
- Binary: `Encoding::ASCII_8BIT`.

These instance methods are relevant:

- #external_encoding: returns the current encoding of the stream as an `Encoding` object.
- #internal_encoding: returns +nil+; a stream does not have an internal encoding.
- #set_encoding: sets the encoding for the stream.
- #set_encoding_by_bom: sets the encoding for the stream to the stream's BOM (byte order mark).

Examples:

```ruby
strio = StringIO.new('foo', 'rt')  # Text mode.
strio.external_encoding # => #<Encoding:UTF-8>
data = "\u9990\u9991\u9992\u9993\u9994"
strio = StringIO.new(data, 'rb') # Binary mode.
strio.external_encoding # => #<Encoding:BINARY (ASCII-8BIT)>
strio = StringIO.new('foo')
strio.external_encoding # => #<Encoding:UTF-8>
strio.set_encoding('US-ASCII')
strio.external_encoding # => #<Encoding:US-ASCII>
```

### Position

A stream has a _position_, and integer offset (in bytes) into the stream.
The initial position of a stream is zero.

#### Getting and Setting the Position

Each of these methods initializes (to zero) the position of a new or re-opened stream:

- ::new: returns a new stream.
- ::open: passes a new stream to the block.
- #reopen: re-initializes the stream.

Each of these methods queries, gets, or sets the position, without otherwise changing the stream:

- #eof?: returns whether the position is at end-of-stream.
- #pos: returns the position.
- #pos=: sets the position.
- #rewind: sets the position to zero.
- #seek: sets the position.

Examples:

```ruby
strio = StringIO.new('foobar')
strio.pos  # => 0
strio.pos = 3
strio.pos  # => 3
strio.eof? # => false
strio.rewind
strio.pos  # => 0
strio.seek(0, IO::SEEK_END)
strio.pos  # => 6
strio.eof? # => true
```

#### Position Before and After Reading

Except for #pread, a stream reading method (see [Basic Reading][basic reading])
begins reading at the current position.

Except for #pread, a read method advances the position past the read substring.

Examples:

```ruby
strio = StringIO.new(TEXT)
strio.string # => "First line\nSecond line\n\nFourth line\nFifth line\n"
strio.pos    # => 0
strio.getc   # => "F"
strio.pos    # => 1
strio.gets   # => "irst line\n"
strio.pos    # => 11
strio.pos = 24
strio.gets   # => "Fourth line\n"
strio.pos    # => 36

strio = StringIO.new('こんにちは')  # Five 3-byte characters.
strio.pos = 0  # At first byte of first character.
strio.read     # => "こんにちは"
strio.pos = 1  # At second byte of first character.
strio.read     # => "\x81\x93んにちは"
strio.pos = 2  # At third byte of first character.
strio.read     # => "\x93んにちは"
strio.pos = 3  # At first byte of second character.
strio.read     # => "んにちは"

strio = StringIO.new(TEXT)
strio.pos = 15
a = []
strio.each_line {|line| a.push(line) }
a         # => ["nd line\n", "\n", "Fourth line\n", "Fifth line\n"]
strio.pos # => 47  ## End-of-stream.
```

#### Position Before and After Writing

Each of these methods begins writing at the current position,
and advances the position to the end of the written substring:

- #putc: writes the given character.
- #write: writes the given objects as strings.
- [Kernel#puts][kernel#puts]: writes given objects as strings, each followed by newline.

Examples:

```ruby
strio = StringIO.new('foo')
strio.pos    # => 0
strio.putc('b')
strio.string # => "boo"
strio.pos    # => 1
strio.write('r')
strio.string # => "bro"
strio.pos    # => 2
strio.puts('ew')
strio.string # => "brew\n"
strio.pos    # => 5
strio.pos = 8
strio.write('foo')
strio.string # => "brew\n\u0000\u0000\u0000foo"
strio.pos    # => 11
```

Each of these methods writes _before_ the current position, and decrements the position
so that the written data is next to be read:

- #ungetbyte: unshifts the given byte.
- #ungetc: unshifts the given character.

Examples:

```ruby
strio = StringIO.new('foo')
strio.pos = 2
strio.ungetc('x')
strio.pos    # => 1
strio.string # => "fxo"
strio.ungetc('x')
strio.pos    # => 0
strio.string # => "xxo"
```

This method does not affect the position:

- #truncate: truncates the stream's string to the given size.

Examples:

```ruby
strio = StringIO.new('foobar')
strio.pos    # => 0
strio.truncate(3)
strio.string # => "foo"
strio.pos    # => 0
strio.pos = 500
strio.truncate(0)
strio.string # => ""
strio.pos    # => 500
```

### Line Number

A stream has a line number, which initially is zero:

- Method #lineno returns the line number.
- Method #lineno= sets the line number.

The line number can be affected by reading (but never by writing);
in general, the line number is incremented each time the record separator (default: `"\n"`) is read.

Examples:

```ruby
strio = StringIO.new(TEXT)
strio.string # => "First line\nSecond line\n\nFourth line\nFifth line\n"
strio.lineno # => 0
strio.gets   # => "First line\n"
strio.lineno # => 1
strio.getc   # => "S"
strio.lineno # => 1
strio.gets   # => "econd line\n"
strio.lineno # => 2
strio.gets   # => "\n"
strio.lineno # => 3
strio.gets   # => "Fourth line\n"
strio.lineno # => 4
```

Setting the position does not affect the line number:

```ruby
strio.pos = 0
strio.lineno # => 4
strio.gets   # => "First line\n"
strio.pos    # => 11
strio.lineno # => 5
```

And setting the line number does not affect the position:

```ruby
strio.lineno = 10
strio.pos    # => 11
strio.gets   # => "Second line\n"
strio.lineno # => 11
strio.pos    # => 23
```

### Open/Closed Streams

A new stream is open for either reading or writing, and may be open for both;
see [Read/Write Mode][read/write mode].

Each of these methods initializes the read/write mode for a new or re-opened stream:

- ::new: returns a new stream.
- ::open: passes a new stream to the block.
- #reopen: re-initializes the stream.

Other relevant methods:

- #close: closes the stream for both reading and writing.
- #close_read: closes the stream for reading.
- #close_write: closes the stream for writing.
- #closed?: returns whether the stream is closed for both reading and writing.
- #closed_read?: returns whether the stream is closed for reading.
- #closed_write?: returns whether the stream is closed for writing.

### BOM (Byte Order Mark)

The string provided for ::new, ::open, or #reopen
may contain an optional [BOM][bom] (byte order mark) at the beginning of the string;
the BOM can affect the stream's encoding.

The BOM (if provided):

- Is stored as part of the stream's string.
- Does _not_ immediately affect the encoding.
- Is _initially_ considered part of the stream.

```ruby
utf8_bom = "\xEF\xBB\xBF"
string = utf8_bom + 'foo'
string.bytes               # => [239, 187, 191, 102, 111, 111]
strio.string.bytes.take(3) # => [239, 187, 191]                  # The BOM.
strio = StringIO.new(string, 'rb')
strio.string.bytes         # => [239, 187, 191, 102, 111, 111]   # BOM is part of the stored string.
strio.external_encoding    # => #<Encoding:BINARY (ASCII-8BIT)>  # Default for a binary stream.
strio.gets                 # => "\xEF\xBB\xBFfoo"                # BOM is part of the stream.
```

You can call instance method #set_encoding_by_bom to "activate" the stored BOM;
after doing so the BOM:

- Is _still_ stored as part of the stream's string.
- _Determines_ (and may have changed) the stream's encoding.
- Is _no longer_ considered part of the stream.

```ruby
strio.set_encoding_by_bom
strio.string.bytes      # => [239, 187, 191, 102, 111, 111]  # BOM is still part of the stored string.
strio.external_encoding # => #<Encoding:UTF-8>               # The new encoding.
strio.rewind            # => 0
strio.gets              # => "foo"                           # BOM is not part of the stream.
```

## Basic Stream \IO

### Basic Reading

You can read from the stream using these instance methods:

- #getbyte: reads and returns the next byte.
- #getc: reads and returns the next character.
- #gets: reads and returns all or part of the next line.
- #read: reads and returns all or part of the remaining data in the stream.
- #readlines: reads the remaining data the stream and returns an array of its lines.
- [Kernel#readline][kernel#readline]: like #gets, but raises an exception if at end-of-stream.

You can iterate over the stream using these instance methods:

- #each_byte: reads each remaining byte, passing it to the block.
- #each_char: reads each remaining character, passing it to the block.
- #each_codepoint: reads each remaining codepoint, passing it to the block.
- #each_line: reads all or part of each remaining line, passing the read string to the block

This instance method is useful in a multi-threaded application:

- #pread: reads and returns all or part of the stream.
 
### Basic Writing

You can write to the stream, advancing the position, using these instance methods:

- #putc: writes a given character.
- #write: writes the given objects as strings.
- [Kernel#puts][kernel#puts] writes given objects as strings, each followed by newline.

You can "unshift" to the stream using these instance methods;
each  writes _before_ the current position, and decrements the position
so that the written data is next to be read.

- #ungetbyte: unshifts the given byte.
- #ungetc: unshifts the given character.

One more writing method:

- #truncate: truncates the stream's string to the given size.

## Line \IO

Reading:

- #gets: reads and returns the next line.
- [Kernel#readline][kernel#readline]: like #gets, but raises an exception if at end-of-stream.
- #readlines: reads the remaining data the stream and returns an array of its lines.
- #each_line: reads each remaining line, passing it to the block

Writing:

- [Kernel#puts][kernel#puts]: writes given objects, each followed by newline.

## Character \IO

Reading:

- #each_char: reads each remaining character, passing it to the block.
- #getc: reads and returns the next character.

Writing:

- #putc: writes the given character.
- #ungetc.: unshifts the given character.

## Byte \IO

Reading:

- #each_byte: reads each remaining byte, passing it to the block.
- #getbyte: reads and returns the next byte.

Writing:

- #ungetbyte: unshifts the given byte.

## Codepoint \IO

Reading:

- #each_codepoint: reads each remaining codepoint, passing it to the block.

[bom]:                https://en.wikipedia.org/wiki/Byte_order_mark
[encodings document]: https://docs.ruby-lang.org/en/master/language/encodings_rdoc.html
[io class]:           https://docs.ruby-lang.org/en/master/IO.html
[kernel#puts]:        https://docs.ruby-lang.org/en/master/Kernel.html#method-i-puts
[kernel#readline]:    https://docs.ruby-lang.org/en/master/Kernel.html#method-i-readline

[basic reading]:         rdoc-ref:StringIO@Basic+Reading
[basic writing]:         rdoc-ref:StringIO@Basic+Writing
[bom (byte order mark)]: rdoc-ref:StringIO@BOM+Byte+Order+Mark
[data mode]:             rdoc-ref:StringIO@Data+Mode
[encodings]:             rdoc-ref:StringIO@Encodings
[end-of-stream]:         rdoc-ref:StringIO@End-of-Stream
[line number]:           rdoc-ref:StringIO@Line+Number
[open/closed streams]:   rdoc-ref:StringIO@OpenClosed+Streams
[position]:              rdoc-ref:StringIO@Position
[read/write mode]:       rdoc-ref:StringIO@ReadWrite+Mode
