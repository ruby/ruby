# Packed \Data

## Quick Reference

These tables summarize the directives for packing and unpacking.

### For Integers

| Directive             | Meaning                                                                                             |
|-----------------------|-----------------------------------------------------------------------------------------------------|
| `C`                   | 8-bit unsigned (`unsigned char`)                                                                    |
| `S`                   | 16-bit unsigned, native endian (`uint16_t`)                                                         |
| `L`                   | 32-bit unsigned, native endian (`uint32_t`)                                                         |
| `Q`                   | 64-bit unsigned, native endian (`uint64_t`)                                                         |
| `J`                   | pointer width unsigned, native endian (`uintptr_t`)                                                 |
|                       |                                                                                                     |
| `c`                   | 8-bit signed (`signed char`)                                                                        |
| `s`                   | 16-bit signed, native endian (`int16_t`)                                                            |
| `l`                   | 32-bit signed, native endian (`int32_t`)                                                            |
| `q`                   | 64-bit signed, native endian (`int64_t`)                                                            |
| `j`                   | pointer width signed, native endian (`intptr_t`)                                                    |
|                       |                                                                                                     |
| `S_` `S!`             | `unsigned short`, native endian                                                                     |
| `I` `I_` `I!`         | `unsigned int`, native endian                                                                       |
| `L_` `L!`             | `unsigned long`, native endian                                                                      |
| `Q_` `Q!`             | `unsigned long long`, native endian; (raises ArgumentError if the platform has no `long long` type) |
| `J!`                  | `uintptr_t`, native endian (same with `J`)                                                          |
|                       |                                                                                                     |
| `s_` `s!`             | `signed short`, native endian                                                                       |
| `i` `i_` `i!`         | `signed int`, native endian                                                                         |
| `l_` `l!`             | `signed long`, native endian                                                                        |
| `q_` `q!`             | `signed long long`, native endian; (raises ArgumentError if the platform has no `long long` type)   |
| `j!`                  | `intptr_t`, native endian (same with `j`)                                                           |
|                       |                                                                                                     |
| `S>` `s>` `S!>` `s!>` | each the same as the directive without `>`, but big endian; `S>` is the same as `n`                 |
| `L>` `l>` `L!>` `l!>` | `L>` is the same as `N`                                                                             |
| `I!>` `i!>`           |                                                                                                     |
| `Q>` `q>` `Q!>` `q!>` |                                                                                                     |
| `J>` `j>` `J!>` `j!>` |                                                                                                     |
|                       |                                                                                                     |
| `S<` `s<` `S!<` `s!<` | each the same as the directive without `<`, but little endian; `S<` is the same as `v`              |
| `L<` `l<` `L!<` `l!<` | `L<` is the same as `V`                                                                             |
| `I!<` `i!<`           |                                                                                                     |
| `Q<` `q<` `Q!<` `q!<` |                                                                                                     |
| `J<` `j<` `J!<` `j!<` |                                                                                                     |
|                       |                                                                                                     |
| `n`                   | 16-bit unsigned, network (big-endian) byte order                                                    |
| `N`                   | 32-bit unsigned, network (big-endian) byte order                                                    |
| `v`                   | 16-bit unsigned, VAX (little-endian) byte order                                                     |
| `V`                   | 32-bit unsigned, VAX (little-endian) byte order                                                     |
|                       |                                                                                                     |
| `U`                   | UTF-8 character                                                                                     |
| `w`                   | BER-compressed integer                                                                              |

### For Floats

| Directive | Meaning                                           |
|-----------|---------------------------------------------------|
| `D` `d`   | double-precision, native format                   |
| `F` `f`   | single-precision, native format                   |
| `E`       | double-precision, little-endian byte order        |
| `e`       | single-precision, little-endian byte order        |
| `G`       | double-precision, network (big-endian) byte order |
| `g`       | single-precision, network (big-endian) byte order |

### For Strings

| Directive | Meaning                                                                                        |
|-----------|------------------------------------------------------------------------------------------------|
| `A`       | arbitrary binary string (remove trailing nulls and ASCII spaces)                               |
| `a`       | arbitrary binary string                                                                        |
| `Z`       | null-terminated string                                                                         |
| `B`       | bit string (MSB first)                                                                         |
| `b`       | bit string (LSB first)                                                                         |
| `H`       | hex string (high nibble first)                                                                 |
| `h`       | hex string (low nibble first)                                                                  |
| `u`       | UU-encoded string                                                                              |
| `M`       | quoted-printable, MIME encoding (see RFC2045)                                                  |
| `m`       | base64 encoded string (RFC 2045) (default) (base64 encoded string (RFC 4648) if followed by 0) |
| `P`       | pointer to a structure (fixed-length string)                                                   |
| `p`       | pointer to a null-terminated string                                                            |

### Additional Directives for Packing

| Directive | Meaning                    |
|-----------|----------------------------|
| `@`       | moves to absolute position |
| `X`       | back up a byte             |
| `x`       | null byte                  |

### Additional Directives for Unpacking

| Directive | Meaning                                         |
|-----------|-------------------------------------------------|
| `@`       | skip to the offset given by the length argument |
| `X`       | skip backward one byte                          |
| `x`       | skip forward one byte                           |

## Packing and Unpacking

Certain Ruby core methods deal with packing and unpacking data:

- Method Array#pack:
  Formats each element in array `self` into a binary string;
  returns that string.
- Method String#unpack:
  Extracts data from string `self`,
  forming objects that become the elements of a new array;
  returns that array.
- Method String#unpack1:
  Does the same, but unpacks and returns only the first extracted object.

Each of these methods accepts a string `template`,
consisting of zero or more _directive_ characters,
each followed by zero or more _modifier_ characters.

Examples (directive `'C'` specifies '`unsigned character`'):

```ruby
[65].pack('C')      # => "A"  # One element, one directive.
[65, 66].pack('CC') # => "AB" # Two elements, two directives.
[65, 66].pack('C')  # => "A"  # Extra element is ignored.
[65].pack('')       # => ""   # No directives.
[65].pack('CC')               # Extra directive raises ArgumentError.
```

```ruby
'A'.unpack('C')   # => [65]      # One character, one directive.
'AB'.unpack('CC') # => [65, 66]  # Two characters, two directives.
'AB'.unpack('C')  # => [65]      # Extra character is ignored.
'A'.unpack('CC')  # => [65, nil] # Extra directive generates nil.
'AB'.unpack('')   # => []        # No directives.
```

The string `template` may contain any mixture of valid directives
(directive `'c'` specifies 'signed character'):

```ruby
[65, -1].pack('cC')  # => "A\xFF"
"A\xFF".unpack('cC') # => [65, 255]
```

The string `template` may contain whitespace (which is ignored)
and comments, each of which begins with character `'#'`
and continues up to and including the next following newline:

```ruby
[0,1].pack("  C  #foo \n  C  ")    # => "\x00\x01"
"\0\1".unpack("  C  #foo \n  C  ") # => [0, 1]
```

Any directive may be followed by either of these modifiers:

- `'*'` - The directive is to be applied as many times as needed:

    ```ruby
    [65, 66].pack('C*') # => "AB"
    'AB'.unpack('C*')   # => [65, 66]
    ```

- \Integer `count` - The directive is to be applied `count` times:

    ```ruby
    [65, 66].pack('C2') # => "AB"
    [65, 66].pack('C3') # Raises ArgumentError.
    'AB'.unpack('C2')   # => [65, 66]
    'AB'.unpack('C3')   # => [65, 66, nil]
    ```

    Note: Directives in `%w[A a Z m]` use `count` differently;
    see [\String Directives][rdoc-ref:@String+Directives].

If elements don't fit the provided directive, only least significant bits are encoded:

```ruby
[257].pack("C").unpack("C") # => [1]
```

## Packing Method

Method Array#pack accepts optional keyword argument
`buffer` that specifies the target string (instead of a new string):

```ruby
[65, 66].pack('C*', buffer: 'foo') # => "fooAB"
```

The method can accept a block:

```ruby
# Packed string is passed to the block.
[65, 66].pack('C*') {|s| p s }    # => "AB"
```

## Unpacking Methods

Methods String#unpack and String#unpack1 each accept
an optional keyword argument `offset` that specifies an offset
into the string:

```ruby
'ABC'.unpack('C*', offset: 1)  # => [66, 67]
'ABC'.unpack1('C*', offset: 1) # => 66
```

Both methods can accept a block:

```ruby
# Each unpacked object is passed to the block.
ret = []
"ABCD".unpack("C*") {|c| ret << c }
ret # => [65, 66, 67, 68]
```

```ruby
# The single unpacked object is passed to the block.
'AB'.unpack1('C*') {|ele| p ele } # => 65
```

## \Integer Directives

Each integer directive specifies the packing or unpacking
for one element in the input or output array.

### 8-Bit \Integer Directives

- `'c'` - 8-bit signed integer
  (like C `signed char`):

    ```ruby
    [0, 1, 255].pack('c*')  # => "\x00\x01\xFF"
    s = [0, 1, -1].pack('c*') # => "\x00\x01\xFF"
    s.unpack('c*') # => [0, 1, -1]
    ```

- `'C'` - 8-bit unsigned integer
  (like C `unsigned char`):

    ```ruby
    [0, 1, 255].pack('C*')    # => "\x00\x01\xFF"
    s = [0, 1, -1].pack('C*') # => "\x00\x01\xFF"
    s.unpack('C*')            # => [0, 1, 255]
    ```

### 16-Bit \Integer Directives

- `'s'` - 16-bit signed integer, native-endian
  (like C `int16_t`):

    ```ruby
    [513, -514].pack('s*')      # => "\x01\x02\xFE\xFD"
    s = [513, 65022].pack('s*') # => "\x01\x02\xFE\xFD"
    s.unpack('s*')              # => [513, -514]
    ```

- `'S'` - 16-bit unsigned integer, native-endian
  (like C `uint16_t`):

    ```ruby
    [513, -514].pack('S*')      # => "\x01\x02\xFE\xFD"
    s = [513, 65022].pack('S*') # => "\x01\x02\xFE\xFD"
    s.unpack('S*')              # => [513, 65022]
    ```

- `'n'` - 16-bit network integer, big-endian:

    ```ruby
    s = [0, 1, -1, 32767, -32768, 65535].pack('n*')
    # => "\x00\x00\x00\x01\xFF\xFF\x7F\xFF\x80\x00\xFF\xFF"
    s.unpack('n*')
    # => [0, 1, 65535, 32767, 32768, 65535]
    ```

- `'v'` - 16-bit VAX integer, little-endian:

    ```ruby
    s = [0, 1, -1, 32767, -32768, 65535].pack('v*')
    # => "\x00\x00\x01\x00\xFF\xFF\xFF\x7F\x00\x80\xFF\xFF"
    s.unpack('v*')
    # => [0, 1, 65535, 32767, 32768, 65535]
    ```

### 32-Bit \Integer Directives

- `'l'` - 32-bit signed integer, native-endian
  (like C `int32_t`):

    ```ruby
    s = [67305985, -50462977].pack('l*')
    # => "\x01\x02\x03\x04\xFF\xFE\xFD\xFC"
    s.unpack('l*')
    # => [67305985, -50462977]
    ```

- `'L'` - 32-bit unsigned integer, native-endian
  (like C `uint32_t`):

    ```ruby
    s = [67305985, 4244504319].pack('L*')
    # => "\x01\x02\x03\x04\xFF\xFE\xFD\xFC"
    s.unpack('L*')
    # => [67305985, 4244504319]
    ```

- `'N'` - 32-bit network integer, big-endian:

    ```ruby
    s = [0,1,-1].pack('N*')
    # => "\x00\x00\x00\x00\x00\x00\x00\x01\xFF\xFF\xFF\xFF"
    s.unpack('N*')
    # => [0, 1, 4294967295]
    ```

- `'V'` - 32-bit VAX integer, little-endian:

     ```ruby
    s = [0,1,-1].pack('V*')
    # => "\x00\x00\x00\x00\x01\x00\x00\x00\xFF\xFF\xFF\xFF"
    s.unpack('v*')
    # => [0, 0, 1, 0, 65535, 65535]
    ```

### 64-Bit \Integer Directives

- `'q'` - 64-bit signed integer, native-endian
  (like C `int64_t`):

    ```ruby
    s = [578437695752307201, -506097522914230529].pack('q*')
    # => "\x01\x02\x03\x04\x05\x06\a\b\xFF\xFE\xFD\xFC\xFB\xFA\xF9\xF8"
    s.unpack('q*')
    # => [578437695752307201, -506097522914230529]
    ```

- `'Q'` - 64-bit unsigned integer, native-endian
  (like C `uint64_t`):

    ```ruby
    s = [578437695752307201, 17940646550795321087].pack('Q*')
    # => "\x01\x02\x03\x04\x05\x06\a\b\xFF\xFE\xFD\xFC\xFB\xFA\xF9\xF8"
    s.unpack('Q*')
    # => [578437695752307201, 17940646550795321087]
    ```

### Platform-Dependent \Integer Directives

- `'i'` - Platform-dependent width signed integer,
  native-endian (like C `int`):

    ```ruby
    s = [67305985, -50462977].pack('i*')
    # => "\x01\x02\x03\x04\xFF\xFE\xFD\xFC"
    s.unpack('i*')
    # => [67305985, -50462977]
    ```

- `'I'` - Platform-dependent width unsigned integer,
  native-endian (like C `unsigned int`):

    ```ruby
    s = [67305985, -50462977].pack('I*')
    # => "\x01\x02\x03\x04\xFF\xFE\xFD\xFC"
    s.unpack('I*')
    # => [67305985, 4244504319]
    ```

- `'j'` - Pointer-width signed integer, native-endian
  (like C `intptr_t`):

    ```ruby
    s = [67305985, -50462977].pack('j*')
    # => "\x01\x02\x03\x04\x00\x00\x00\x00\xFF\xFE\xFD\xFC\xFF\xFF\xFF\xFF"
    s.unpack('j*')
    # => [67305985, -50462977]
    ```

- `'J'` - Pointer-width unsigned integer, native-endian
  (like C `uintptr_t`):

    ```ruby
    s = [67305985, 4244504319].pack('J*')
    # => "\x01\x02\x03\x04\x00\x00\x00\x00\xFF\xFE\xFD\xFC\x00\x00\x00\x00"
    s.unpack('J*')
    # => [67305985, 4244504319]
    ```

### Other \Integer Directives

- `'U'` - UTF-8 character:

    ```ruby
    s = [4194304].pack('U*')
    # => "\xF8\x90\x80\x80\x80"
    s.unpack('U*')
    # => [4194304]
    ```

- `'w'` - BER-encoded integer
  (see {BER encoding}[https://en.wikipedia.org/wiki/X.690#BER_encoding]):

    ```ruby
    s = [1073741823].pack('w*')
    # => "\x83\xFF\xFF\xFF\x7F"
    s.unpack('w*')
    # => [1073741823]
    ```

### Modifiers for \Integer Directives

For the following directives, `'!'` or `'_'` modifiers may be
suffixed as underlying platform’s native size.

- `'i'`, `'I'` - C `int`, always native size.
- `'s'`, `'S'` - C `short`.
- `'l'`, `'L'` - C `long`.
- `'q'`, `'Q'` - C `long long`, if available.
- `'j'`, `'J'` - C `intptr_t`, always native size.

Native size modifiers are silently ignored for always native size directives.

The endian modifiers also may be suffixed in the directives above:

- `'>'` - Big-endian.
- `'<'` - Little-endian.

## \Float Directives

Each float directive specifies the packing or unpacking
for one element in the input or output array.

### Single-Precision \Float Directives

- `'F'` or `'f'` - Native format:

    ```ruby
    s = [3.0].pack('F') # => "\x00\x00@@"
    s.unpack('F')       # => [3.0]
    ```

- `'e'` - Little-endian:

    ```ruby
    s = [3.0].pack('e') # => "\x00\x00@@"
    s.unpack('e')       # => [3.0]
    ```

- `'g'` - Big-endian:

    ```ruby
    s = [3.0].pack('g') # => "@@\x00\x00"
    s.unpack('g')       # => [3.0]
    ```

### Double-Precision \Float Directives

- `'D'` or `'d'` - Native format:

    ```ruby
    s = [3.0].pack('D') # => "\x00\x00\x00\x00\x00\x00\b@"
    s.unpack('D')       # => [3.0]
    ```

- `'E'` - Little-endian:

    ```ruby
    s = [3.0].pack('E') # => "\x00\x00\x00\x00\x00\x00\b@"
    s.unpack('E')       # => [3.0]
    ```

- `'G'` - Big-endian:

    ```ruby
    s = [3.0].pack('G') # => "@\b\x00\x00\x00\x00\x00\x00"
    s.unpack('G')       # => [3.0]
    ```

A float directive may be infinity or not-a-number:

```ruby
inf = 1.0/0.0                  # => Infinity
[inf].pack('f')                # => "\x00\x00\x80\x7F"
"\x00\x00\x80\x7F".unpack('f') # => [Infinity]

nan = inf/inf                  # => NaN
[nan].pack('f')                # => "\x00\x00\xC0\x7F"
"\x00\x00\xC0\x7F".unpack('f') # => [NaN]
```

## \String Directives

Each string directive specifies the packing or unpacking
for one byte in the input or output string.

### Binary \String Directives

- `'A'` - Arbitrary binary string (space padded; count is width);
  `nil` is treated as the empty string:

    ```ruby
    ['foo'].pack('A')    # => "f"
    ['foo'].pack('A*')   # => "foo"
    ['foo'].pack('A2')   # => "fo"
    ['foo'].pack('A4')   # => "foo "
    [nil].pack('A')      # => " "
    [nil].pack('A*')     # => ""
    [nil].pack('A2')     # => "  "
    [nil].pack('A4')     # => "    "
    ```

    ```ruby
    "foo\0".unpack('A')      # => ["f"]
    "foo\0".unpack('A4')     # => ["foo"]
    "foo\0bar".unpack('A10') # => ["foo\x00bar"] # Reads past "\0".
    "foo ".unpack('A')       # => ["f"]
    "foo ".unpack('A4')      # => ["foo"]
    "foo".unpack('A4')       # => ["foo"]
    ```

    ```ruby
    japanese = 'こんにちは'
    japanese.size         # => 5
    japanese.bytesize     # => 15
    [japanese].pack('A')  # => "\xE3"
    [japanese].pack('A*') # => "\xE3\x81\x93\xE3\x82\x93\xE3\x81\xAB\xE3\x81\xA1\xE3\x81\xAF"
    japanese.unpack('A')  # => ["\xE3"]
    japanese.unpack('A2') # => ["\xE3\x81"]
    japanese.unpack('A4') # => ["\xE3\x81\x93\xE3"]
    japanese.unpack('A*') # => ["\xE3\x81\x93\xE3\x82\x93\xE3\x81\xAB\xE3\x81\xA1\xE3\x81\xAF"]
    ```

- `'a'` - Arbitrary binary string (null padded; count is width):

    ```ruby
    ["foo"].pack('a')    # => "f"
    ["foo"].pack('a*')   # => "foo"
    ["foo"].pack('a2')   # => "fo"
    ["foo\0"].pack('a4') # => "foo\x00"
    [nil].pack('a')      # => "\x00"
    [nil].pack('a*')     # => ""
    [nil].pack('a2')     # => "\x00\x00"
    [nil].pack('a4')     # => "\x00\x00\x00\x00"
    ```

    ```ruby
    "foo\0".unpack('a')     # => ["f"]
    "foo\0".unpack('a4')    # => ["foo\x00"]
    "foo ".unpack('a4')     # => ["foo "]
    "foo".unpack('a4')      # => ["foo"]
    "foo\0bar".unpack('a4') # => ["foo\x00"] # Reads past "\0".
    ```

- `'Z'` - Same as `'a'`,
  except that null is added or ignored with `'*'`:

    ```ruby
    ["foo"].pack('Z*')   # => "foo\x00"
    [nil].pack('Z*')     # => "\x00"
    ```

    ```ruby
    "foo\0".unpack('Z*')    # => ["foo"]
    "foo".unpack('Z*')      # => ["foo"]
    "foo\0bar".unpack('Z*') # => ["foo"] # Does not read past "\0".
    ```

### Bit \String Directives

- `'B'` - Bit string (high byte first):

    ```ruby
    ['11111111' + '00000000'].pack('B*') # => "\xFF\x00"
    ['10000000' + '01000000'].pack('B*') # => "\x80@"
    ```

    ```ruby
    ['1'].pack('B0') # => ""
    ['1'].pack('B1') # => "\x80"
    ['1'].pack('B2') # => "\x80\x00"
    ['1'].pack('B3') # => "\x80\x00"
    ['1'].pack('B4') # => "\x80\x00\x00"
    ['1'].pack('B5') # => "\x80\x00\x00"
    ['1'].pack('B6') # => "\x80\x00\x00\x00"
    ```

    ```ruby
    "\xff\x00".unpack("B*") # => ["1111111100000000"]
    "\x01\x02".unpack("B*") # => ["0000000100000010"]
    ```

    ```ruby
    "".unpack("B0")     # => [""]
    "\x80".unpack("B1") # => ["1"]
    "\x80".unpack("B2") # => ["10"]
    "\x80".unpack("B3") # => ["100"]
    ```

- `'b'` - Bit string (low byte first):

    ```ruby
    ['11111111' + '00000000'].pack('b*') # => "\xFF\x00"
    ['10000000' + '01000000'].pack('b*') # => "\x01\x02"
    ```

    ```ruby
    ['1'].pack('b0') # => ""
    ['1'].pack('b1') # => "\x01"
    ['1'].pack('b2') # => "\x01\x00"
    ['1'].pack('b3') # => "\x01\x00"
    ['1'].pack('b4') # => "\x01\x00\x00"
    ['1'].pack('b5') # => "\x01\x00\x00"
    ['1'].pack('b6') # => "\x01\x00\x00\x00"
    ```

    ```ruby
    "\xff\x00".unpack("b*") # => ["1111111100000000"]
    "\x01\x02".unpack("b*") # => ["1000000001000000"]
    ```

    ```ruby
    "".unpack("b0")     # => [""]
    "\x01".unpack("b1") # => ["1"]
    "\x01".unpack("b2") # => ["10"]
    "\x01".unpack("b3") # => ["100"]
    ```

### Hex \String Directives

- `'H'` - Hex string (high nibble first):

    ```ruby
    ['10ef'].pack('H*')    # => "\x10\xEF"
    ['10ef'].pack('H0')    # => ""
    ['10ef'].pack('H3')    # => "\x10\xE0"
    ['10ef'].pack('H5')    # => "\x10\xEF\x00"
    ```

    ```ruby
    ['fff'].pack('H3')    # => "\xFF\xF0"
    ['fff'].pack('H4')    # => "\xFF\xF0"
    ['fff'].pack('H5')    # => "\xFF\xF0\x00"
    ['fff'].pack('H6')    # => "\xFF\xF0\x00"
    ['fff'].pack('H7')    # => "\xFF\xF0\x00\x00"
    ['fff'].pack('H8')    # => "\xFF\xF0\x00\x00"
    ```

    ```ruby
    "\x10\xef".unpack('H*')    # => ["10ef"]
    "\x10\xef".unpack('H0')    # => [""]
    "\x10\xef".unpack('H1')    # => ["1"]
    "\x10\xef".unpack('H2')    # => ["10"]
    "\x10\xef".unpack('H3')    # => ["10e"]
    "\x10\xef".unpack('H4')    # => ["10ef"]
    "\x10\xef".unpack('H5')    # => ["10ef"]
    ```

- `'h'` - Hex string (low nibble first):

    ```ruby
    ['10ef'].pack('h*') # => "\x01\xFE"
    ['10ef'].pack('h0') # => ""
    ['10ef'].pack('h3') # => "\x01\x0E"
    ['10ef'].pack('h5') # => "\x01\xFE\x00"
    ```

    ```ruby
    ['fff'].pack('h3') # => "\xFF\x0F"
    ['fff'].pack('h4') # => "\xFF\x0F"
    ['fff'].pack('h5') # => "\xFF\x0F\x00"
    ['fff'].pack('h6') # => "\xFF\x0F\x00"
    ['fff'].pack('h7') # => "\xFF\x0F\x00\x00"
    ['fff'].pack('h8') # => "\xFF\x0F\x00\x00"
    ```

    ```ruby
    "\x01\xfe".unpack('h*') # => ["10ef"]
    "\x01\xfe".unpack('h0') # => [""]
    "\x01\xfe".unpack('h1') # => ["1"]
    "\x01\xfe".unpack('h2') # => ["10"]
    "\x01\xfe".unpack('h3') # => ["10e"]
    "\x01\xfe".unpack('h4') # => ["10ef"]
    "\x01\xfe".unpack('h5') # => ["10ef"]
    ```

### Pointer \String Directives

- `'P'` - Pointer to a structure (fixed-length string):

    ```ruby
    s = ['abc'].pack('P')  # => "\xE0O\x7F\xE5\xA1\x01\x00\x00"
    s.unpack('P*')         # => ["abc"]
    ".".unpack("P")        # => []
    ("\0" * 8).unpack("P") # => [nil]
    [nil].pack("P")        # => "\x00\x00\x00\x00\x00\x00\x00\x00"
    ```

- `'p'` - Pointer to a null-terminated string:

    ```ruby
    s = ['abc'].pack('p')  # => "(\xE4u\xE5\xA1\x01\x00\x00"
    s.unpack('p*')         # => ["abc"]
    ".".unpack("p")        # => []
    ("\0" * 8).unpack("p") # => [nil]
    [nil].pack("p")        # => "\x00\x00\x00\x00\x00\x00\x00\x00"
    ```

### Other \String Directives

- `'M'` - Quoted printable, MIME encoding;
  text mode, but input must use LF and output LF;
  (see {RFC 2045}[https://www.ietf.org/rfc/rfc2045.txt]):

    ```ruby
    ["a b c\td \ne"].pack('M') # => "a b c\td =\n\ne=\n"
    ["\0"].pack('M')           # => "=00=\n"
    ```

    ```ruby
    ["a"*1023].pack('M') == ("a"*73+"=\n")*14+"a=\n"     # => true
    ("a"*73+"=\na=\n").unpack('M') == ["a"*74]           # => true
    (("a"*73+"=\n")*14+"a=\n").unpack('M') == ["a"*1023] # => true
    ```

    ```ruby
    "a b c\td =\n\ne=\n".unpack('M')    # => ["a b c\td \ne"]
    "=00=\n".unpack('M')    # => ["\x00"]
    ```

    ```ruby
    "pre=31=32=33after".unpack('M') # => ["pre123after"]
    "pre=\nafter".unpack('M')       # => ["preafter"]
    "pre=\r\nafter".unpack('M')     # => ["preafter"]
    "pre=".unpack('M')              # => ["pre="]
    "pre=\r".unpack('M')            # => ["pre=\r"]
    "pre=hoge".unpack('M')          # => ["pre=hoge"]
    "pre==31after".unpack('M')      # => ["pre==31after"]
    "pre===31after".unpack('M')     # => ["pre===31after"]
    ```

- `'m'` - Base64 encoded string;
  count specifies input bytes between each newline,
  rounded down to nearest multiple of 3;
  if count is zero, no newlines are added;
  (see {RFC 4648}[https://www.ietf.org/rfc/rfc4648.txt]):

    ```ruby
    [""].pack('m')             # => ""
    ["\0"].pack('m')           # => "AA==\n"
    ["\0\0"].pack('m')         # => "AAA=\n"
    ["\0\0\0"].pack('m')       # => "AAAA\n"
    ["\377"].pack('m')         # => "/w==\n"
    ["\377\377"].pack('m')     # => "//8=\n"
    ["\377\377\377"].pack('m') # => "////\n"
    ```

    ```ruby
    "".unpack('m')       # => [""]
    "AA==\n".unpack('m') # => ["\x00"]
    "AAA=\n".unpack('m') # => ["\x00\x00"]
    "AAAA\n".unpack('m') # => ["\x00\x00\x00"]
    "/w==\n".unpack('m') # => ["\xFF"]
    "//8=\n".unpack('m') # => ["\xFF\xFF"]
    "////\n".unpack('m') # => ["\xFF\xFF\xFF"]
    "A\n".unpack('m')    # => [""]
    "AA\n".unpack('m')   # => ["\x00"]
    "AA=\n".unpack('m')  # => ["\x00"]
    "AAA\n".unpack('m')  # => ["\x00\x00"]
    ```

    ```ruby
    [""].pack('m0')             # => ""
    ["\0"].pack('m0')           # => "AA=="
    ["\0\0"].pack('m0')         # => "AAA="
    ["\0\0\0"].pack('m0')       # => "AAAA"
    ["\377"].pack('m0')         # => "/w=="
    ["\377\377"].pack('m0')     # => "//8="
    ["\377\377\377"].pack('m0') # => "////"
    ```

    ```ruby
    "".unpack('m0')     # => [""]
    "AA==".unpack('m0') # => ["\x00"]
    "AAA=".unpack('m0') # => ["\x00\x00"]
    "AAAA".unpack('m0') # => ["\x00\x00\x00"]
    "/w==".unpack('m0') # => ["\xFF"]
    "//8=".unpack('m0') # => ["\xFF\xFF"]
    "////".unpack('m0') # => ["\xFF\xFF\xFF"]
    ```

- `'u'` - UU-encoded string:

    ```ruby
    [""].pack("u")        # => ""
    ["a"].pack("u")       # => "!80``\n"
    ["aaa"].pack("u")     # => "#86%A\n"
    ```

    ```ruby
    "".unpack("u")        # => [""]
    "#86)C\n".unpack("u") # => ["abc"]
    ```

## Offset Directives

- `'@'` - Begin packing at the given byte offset;
  for packing, null fill or shrink if necessary:

    ```ruby
    [1, 2].pack("C@0C")     # => "\x02"
    [1, 2].pack("C@1C")     # => "\x01\x02"
    [1, 2].pack("C@5C")     # => "\x01\x00\x00\x00\x00\x02"
    [*1..5].pack("CCCC@2C") # => "\x01\x02\x05"
    ```

  For unpacking, cannot to move to outside the string:

    ```ruby
    "\x01\x00\x00\x02".unpack("C@3C") # => [1, 2]
    "\x00".unpack("@1C")              # => [nil]
    "\x00".unpack("@2C")              # Raises ArgumentError.
    ```

- `'X'` - For packing, shrink for the given byte offset:

    ```ruby
    [0, 1, 2].pack("CCXC")    # => "\x00\x02"
    [0, 1, 2].pack("CCX2C")   # => "\x02"
    ```

  For unpacking; rewind unpacking position for the given byte offset:

    ```ruby
    "\x00\x02".unpack("CCXC") # => [0, 2, 2]
    ```

  Cannot to move to outside the string:

    ```ruby
    [0, 1, 2].pack("CCX3C")   # Raises ArgumentError.
    "\x00\x02".unpack("CX3C") # Raises ArgumentError.
    ```

- `'x'` - Begin packing at after the given byte offset;
  for packing, null fill if necessary:

    ```ruby
    [].pack("x0")                # => ""
    [].pack("x")                 # => "\x00"
    [].pack("x8")                # => "\x00\x00\x00\x00\x00\x00\x00\x00"
    ```

  For unpacking, cannot to move to outside the string:

  ```ruby
  "\x00\x00\x02".unpack("CxC") # => [0, 2]
  "\x00\x00\x02".unpack("x3C") # => [nil]
  "\x00\x00\x02".unpack("x4C") # Raises ArgumentError
  ```
