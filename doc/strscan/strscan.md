\Class `StringScanner` supports processing a stored string as a stream;
this code creates a new `StringScanner` object with string `'foobarbaz'`:

```rb
require 'strscan'
scanner = StringScanner.new('foobarbaz')
```

## About the Examples

All examples here assume that `StringScanner` has been required:

```rb
require 'strscan'
```

Some examples here assume that these constants are defined:

```rb
MULTILINE_TEXT = <<~EOT
Go placidly amid the noise and haste,
and remember what peace there may be in silence.
EOT

HIRAGANA_TEXT = 'こんにちは'

ENGLISH_TEXT = 'Hello'
```

Some examples here assume that certain helper methods are defined:

- `put_situation(scanner)`:
  Displays the values of the scanner's
  methods #pos, #charpos, #rest, and #rest_size.
- `put_match_values(scanner)`:
  Displays the scanner's [match values][9].
- `match_values_cleared?(scanner)`:
  Returns whether the scanner's [match values][9] are cleared.

See examples [here][ext/strscan/helper_methods_md.html].

## The `StringScanner` \Object

This code creates a `StringScanner` object
(we'll call it simply a _scanner_),
and shows some of its basic properties:

```rb
scanner = StringScanner.new('foobarbaz')
scanner.string # => "foobarbaz"
put_situation(scanner)
# Situation:
#   pos:       0
#   charpos:   0
#   rest:      "foobarbaz"
#   rest_size: 9
```

The scanner has:

* A <i>stored string</i>, which is:

    * Initially set by StringScanner.new(string) to the given `string`
      (`'foobarbaz'` in the example above).
    * Modifiable by methods #string=(new_string) and #concat(more_string).
    * Returned by method #string.

    More at [Stored String][1] below.

* A _position_;
  a zero-based index into the bytes of the stored string (_not_ into its characters):

    * Initially set by StringScanner.new to `0`.
    * Returned by method #pos.
    * Modifiable explicitly by methods #reset, #terminate, and #pos=(new_pos).
    * Modifiable implicitly (various traversing methods, among others).

    More at [Byte Position][2] below.

* A <i>target substring</i>,
  which is a trailing substring of the stored string;
  it extends from the current position to the end of the stored string:

    * Initially set by StringScanner.new(string) to the given `string`
      (`'foobarbaz'` in the example above).
    * Returned by method #rest.
    * Modified by any modification to either the stored string or the position.

    <b>Most importantly</b>:
    the searching and traversing methods operate on the target substring,
    which may be (and often is) less than the entire stored string.

    More at [Target Substring][3] below.

## Stored \String

The <i>stored string</i> is the string stored in the `StringScanner` object.

Each of these methods sets, modifies, or returns the stored string:

| Method               | Effect                                          |
|----------------------|-------------------------------------------------|
| ::new(string)        | Creates a new scanner for the given string.     |
| #string=(new_string) | Replaces the existing stored string.            |
| #concat(more_string) | Appends a string to the existing stored string. |
| #string              | Returns the stored string.                      |

## Positions

A `StringScanner` object maintains a zero-based <i>byte position</i>
and a zero-based <i>character position</i>.

Each of these methods explicitly sets positions:

| Method                   | Effect                                                   |
|--------------------------|----------------------------------------------------------|
| #reset                   | Sets both positions to zero (begining of stored string). |
| #terminate               | Sets both positions to the end of the stored string.     |
| #pos=(new_byte_position) | Sets byte position; adjusts character position.          |

### Byte Position (Position)

The byte position (or simply _position_)
is a zero-based index into the bytes in the scanner's stored string;
for a new `StringScanner` object, the byte position is zero.

When the byte position is:

* Zero (at the beginning), the target substring is the entire stored string.
* Equal to the size of the stored string (at the end),
  the target substring is the empty string `''`.

To get or set the byte position:

* \#pos: returns the byte position.
* \#pos=(new_pos): sets the byte position.

Many methods use the byte position as the basis for finding matches;
many others set, increment, or decrement the byte position:

```rb
scanner = StringScanner.new('foobar')
scanner.pos # => 0
scanner.scan(/foo/) # => "foo" # Match found.
scanner.pos         # => 3     # Byte position incremented.
scanner.scan(/foo/) # => nil   # Match not found.
scanner.pos # => 3             # Byte position not changed.
```

Some methods implicitly modify the byte position;
see:

* [Setting the Target Substring][4].
* [Traversing the Target Substring][5].

The values of these methods are derived directly from the values of #pos and #string:

- \#charpos: the [character position][7].
- \#rest: the [target substring][3].
- \#rest_size: `rest.size`.

### Character Position

The character position is a zero-based index into the _characters_
in the stored string;
for a new `StringScanner` object, the character position is zero.

\Method #charpos returns the character position;
its value may not be reset explicitly.

Some methods change (increment or reset) the character position;
see:

* [Setting the Target Substring][4].
* [Traversing the Target Substring][5].

Example (string includes multi-byte characters):

```rb
scanner = StringScanner.new(ENGLISH_TEXT) # Five 1-byte characters.
scanner.concat(HIRAGANA_TEXT)             # Five 3-byte characters
scanner.string # => "Helloこんにちは"       # Twenty bytes in all.
put_situation(scanner)
# Situation:
#   pos:       0
#   charpos:   0
#   rest:      "Helloこんにちは"
#   rest_size: 20
scanner.scan(/Hello/) # => "Hello" # Five 1-byte characters.
put_situation(scanner)
# Situation:
#   pos:       5
#   charpos:   5
#   rest:      "こんにちは"
#   rest_size: 15
scanner.getch         # => "こ"    # One 3-byte character.
put_situation(scanner)
# Situation:
#   pos:       8
#   charpos:   6
#   rest:      "んにちは"
#   rest_size: 12
```

## Target Substring

The target substring is the the part of the [stored string][1]
that extends from the current [byte position][2] to the end of the stored string;
it is always either:

- The entire stored string (byte position is zero).
- A trailing substring of the stored string (byte position positive).

The target substring is returned by method #rest,
and its size is returned by method #rest_size.

Examples:

```rb
scanner = StringScanner.new('foobarbaz')
put_situation(scanner)
# Situation:
#   pos:       0
#   charpos:   0
#   rest:      "foobarbaz"
#   rest_size: 9
scanner.pos = 3
put_situation(scanner)
# Situation:
#   pos:       3
#   charpos:   3
#   rest:      "barbaz"
#   rest_size: 6
scanner.pos = 9
put_situation(scanner)
# Situation:
#   pos:       9
#   charpos:   9
#   rest:      ""
#   rest_size: 0
```

### Setting the Target Substring

The target substring is set whenever:

* The [stored string][1] is set (position reset to zero; target substring set to stored string).
* The [byte position][2] is set (target substring adjusted accordingly).

### Querying the Target Substring

This table summarizes (details and examples at the links):

| Method     | Returns                           |
|------------|-----------------------------------|
| #rest      | Target substring.                 |
| #rest_size | Size (bytes) of target substring. |

### Searching the Target Substring

A _search_ method examines the target substring,
but does not advance the [positions][11]
or (by implication) shorten the target substring.

This table summarizes (details and examples at the links):

| Method                | Returns                                       | Sets Match Values? |
|-----------------------|-----------------------------------------------|--------------------|
| #check(pattern)       | Matched leading substring or +nil+.           | Yes.               |
| #check_until(pattern) | Matched substring (anywhere) or +nil+.        | Yes.               |
| #exist?(pattern)      | Matched substring (anywhere) end index.       | Yes.               |
| #match?(pattern)      | Size of matched leading substring or +nil+.   | Yes.               |
| #peek(size)           | Leading substring of given length (bytes).    | No.                |
| #peek_byte            | Integer leading byte or +nil+.                | No.                |
| #rest                 | Target substring (from byte position to end). | No.                |

### Traversing the Target Substring

A _traversal_ method examines the target substring,
and, if successful:

- Advances the [positions][11].
- Shortens the target substring.


This table summarizes (details and examples at links):

| Method               | Returns                                              | Sets Match Values? |
|----------------------|------------------------------------------------------|--------------------|
| #get_byte            | Leading byte or +nil+.                               | No.                |
| #getch               | Leading character or +nil+.                          | No.                |
| #scan(pattern)       | Matched leading substring or +nil+.                  | Yes.               |
| #scan_byte           | Integer leading byte or +nil+.                       | No.                |
| #scan_until(pattern) | Matched substring (anywhere) or +nil+.               | Yes.               |
| #skip(pattern)       | Matched leading substring size or +nil+.             | Yes.               |
| #skip_until(pattern) | Position delta to end-of-matched-substring or +nil+. | Yes.               |
| #unscan              | +self+.                                              | No.                |

## Querying the Scanner

Each of these methods queries the scanner object
without modifying it (details and examples at links)

| Method              | Returns                          |
|---------------------|----------------------------------|
| #beginning_of_line? | +true+ or +false+.               |
| #charpos            | Character position.              |
| #eos?               | +true+ or +false+.               |
| #fixed_anchor?      | +true+ or +false+.               |
| #inspect            | String representation of +self+. |
| #pos                | Byte position.                   |
| #rest               | Target substring.                |
| #rest_size          | Size of target substring.        |
| #string             | Stored string.                   |

## Matching

`StringScanner` implements pattern matching via Ruby class [Regexp][6],
and its matching behaviors are the same as Ruby's
except for the [fixed-anchor property][10].

### Matcher Methods

Each <i>matcher method</i> takes a single argument `pattern`,
and attempts to find a matching substring in the [target substring][3].

| Method       | Pattern Type      | Matches Target Substring | Success Return     | May Update Positions? |
|--------------|-------------------|--------------------------|--------------------|-----------------------|
| #check       | Regexp or String. | At beginning.            | Matched substring. | No.                   |
| #check_until | Regexp or String. | Anywhere.                | Substring.         | No.                   |
| #match?      | Regexp or String. | At beginning.            | Match size.        | No.                   |
| #exist?      | Regexp or String. | Anywhere.                | Substring size.    | No.                   |
| #scan        | Regexp or String. | At beginning.            | Matched substring. | Yes.                  |
| #scan_until  | Regexp or String. | Anywhere.                | Substring.         | Yes.                  |
| #skip        | Regexp or String. | At beginning.            | Match size.        | Yes.                  |
| #skip_until  | Regexp or String. | Anywhere.                | Substring size.    | Yes.                  |

<br>

Which matcher you choose will depend on:

- Where you want to find a match:

    - Only at the beginning of the target substring:
      #check, #match?, #scan, #skip.
    - Anywhere in the target substring:
      #check_until, #exist?, #scan_until, #skip_until.

- Whether you want to:

    - Traverse, by advancing the positions:
      #scan, #scan_until, #skip, #skip_until.
    - Keep the positions unchanged:
      #check, #check_until, #match?, #exist?.

- What you want for the return value:

    - The matched substring: #check, #scan.
    - The substring: #check_until, #scan_until.
    - The match size: #match?, #skip.
    - The substring size: #exist?, #skip_until.

### Match Values

The <i>match values</i> in a `StringScanner` object
generally contain the results of the most recent attempted match.

Each match value may be thought of as:

* _Clear_: Initially, or after an unsuccessful match attempt:
  usually, `false`, `nil`, or `{}`.
* _Set_: After a successful match attempt:
  `true`, string, array, or hash.

Each of these methods clears match values:

- ::new(string).
- \#reset.
- \#terminate.

Each of these methods attempts a match based on a pattern,
and either sets match values (if successful) or clears them (if not);

- \#check(pattern)
- \#check_until(pattern)
- \#exist?(pattern)
- \#match?(pattern)
- \#scan(pattern)
- \#scan_until(pattern)
- \#skip(pattern)
- \#skip_until(pattern)

#### Basic Match Values

Basic match values are those not related to captures.

Each of these methods returns a basic match value:

| Method          | Return After Match                     | Return After No Match |
|-----------------|----------------------------------------|-----------------------|
| #matched?       | +true+.                                | +false+.              |
| #matched_size   | Size of matched substring.             | +nil+.                |
| #matched        | Matched substring.                     | +nil+.                |
| #pre_match      | Substring preceding matched substring. | +nil+.                |
| #post_match     | Substring following matched substring. | +nil+.                |

<br>

See examples below.

#### Captured Match Values

Captured match values are those related to [captures][16].

Each of these methods returns a captured match value:

| Method          | Return After Match                      | Return After No Match |
|-----------------|-----------------------------------------|-----------------------|
| #size           | Count of captured substrings.           | +nil+.                |
| #[](n)          | <tt>n</tt>th captured substring.        | +nil+.                |
| #captures       | Array of all captured substrings.       | +nil+.                |
| #values_at(*n)  | Array of specified captured substrings. | +nil+.                |
| #named_captures | Hash of named captures.                 | <tt>{}</tt>.          |

<br>

See examples below.

#### Match Values Examples

Successful basic match attempt (no captures):

```rb
scanner = StringScanner.new('foobarbaz')
scanner.exist?(/bar/)
put_match_values(scanner)
# Basic match values:
#   matched?:       true
#   matched_size:   3
#   pre_match:      "foo"
#   matched  :      "bar"
#   post_match:     "baz"
# Captured match values:
#   size:           1
#   captures:       []
#   named_captures: {}
#   values_at:      ["bar", nil]
#   []:
#     [0]:          "bar"
#     [1]:          nil
```

Failed basic match attempt (no captures);

```rb
scanner = StringScanner.new('foobarbaz')
scanner.exist?(/nope/)
match_values_cleared?(scanner) # => true
```

Successful unnamed capture match attempt:

```rb
scanner = StringScanner.new('foobarbazbatbam')
scanner.exist?(/(foo)bar(baz)bat(bam)/)
put_match_values(scanner)
# Basic match values:
#   matched?:       true
#   matched_size:   15
#   pre_match:      ""
#   matched  :      "foobarbazbatbam"
#   post_match:     ""
# Captured match values:
#   size:           4
#   captures:       ["foo", "baz", "bam"]
#   named_captures: {}
#   values_at:      ["foobarbazbatbam", "foo", "baz", "bam", nil]
#   []:
#     [0]:          "foobarbazbatbam"
#     [1]:          "foo"
#     [2]:          "baz"
#     [3]:          "bam"
#     [4]:          nil
```

Successful named capture match attempt;
same as unnamed above, except for #named_captures:

```rb
scanner = StringScanner.new('foobarbazbatbam')
scanner.exist?(/(?<x>foo)bar(?<y>baz)bat(?<z>bam)/)
scanner.named_captures # => {"x"=>"foo", "y"=>"baz", "z"=>"bam"}
```

Failed unnamed capture match attempt:

```rb
scanner = StringScanner.new('somestring')
scanner.exist?(/(foo)bar(baz)bat(bam)/)
match_values_cleared?(scanner) # => true
```

Failed named capture match attempt;
same as unnamed above, except for #named_captures:

```rb
scanner = StringScanner.new('somestring')
scanner.exist?(/(?<x>foo)bar(?<y>baz)bat(?<z>bam)/)
match_values_cleared?(scanner) # => false
scanner.named_captures # => {"x"=>nil, "y"=>nil, "z"=>nil}
```

## Fixed-Anchor Property

Pattern matching in `StringScanner` is the same as in Ruby's,
except for its fixed-anchor property,
which determines the meaning of `'\A'`:

* `false` (the default): matches the current byte position.

    ```rb
    scanner = StringScanner.new('foobar')
    scanner.scan(/\A./) # => "f"
    scanner.scan(/\A./) # => "o"
    scanner.scan(/\A./) # => "o"
    scanner.scan(/\A./) # => "b"
    ```

* `true`: matches the beginning of the target substring;
  never matches unless the byte position is zero:

    ```rb
    scanner = StringScanner.new('foobar', fixed_anchor: true)
    scanner.scan(/\A./) # => "f"
    scanner.scan(/\A./) # => nil
    scanner.reset
    scanner.scan(/\A./) # => "f"
    ```

The fixed-anchor property is set when the `StringScanner` object is created,
and may not be modified
(see StringScanner.new);
method #fixed_anchor? returns the setting.

