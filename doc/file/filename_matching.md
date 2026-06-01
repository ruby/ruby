## Filename Matching

Filename matching is a pattern-matching feature implemented in certain Ruby methods:

- File.fnmatch.
- Pathname#fnmatch.

Each `fnmatch` method matches a pattern against a string _path_;
these methods operate only on strings, and do not access the file system.

These are quite different from filename globbing methods (not discussed here),
which match patterns against string paths found in the actual file system:

- Dir.glob.
- Pathname.glob.
- Pathname#glob.

### Patterns

These are the basic elements of filename matching patterns;
see the sections below for details:

|         Pattern          | Meaning                                    | Examples                     |
|:------------------------:|--------------------------------------------|------------------------------|
|      Simple string.      | Matches itself.                            | `'Rakefile'`, `'LEGAL'`      |
|          `'*'`           | Matches any sequence of characters.        | `'*.txt'`                    |
|           `'?'`          | Matches any single character.              | `'?.txt'`                    |
| `'[abc]'`,<br>`'[^abc]'` | Matches a single character from a set.     | `'x[abc]y'`,<br>`'x[^abc]y'` |
| `'[a-z]`',<br>`'[^a-z]'` | Matches a single character from a range.   | `'x[0-9]y'`,<br>`'x[^0-9]y'` |
|          `'**'`          | Matches a directory-like substring.        | `'**/test.rb'`               |
|          `'\'`           | Escapes the next character.                | `'\\*'`, `'\?'`              |

There is one other pattern, for alternatives, that is disabled by default;
see [`File::FNM_EXTGLOB`](#constant-filefnmextglob) below.

#### Simple \String

A "simple string" is one that does not contain special filename-matching patterns;
see the table above.

A simple string matches itself:

```ruby
File.fnmatch('xyzzy', 'xyzzy')                 # => true
File.fnmatch('one_two_three', 'one_two_three') # => true
File.fnmatch('123', '123')                     # => true
File.fnmatch('Form 27B/6', 'Form 27B/6')       # => true
File.fnmatch('bcd', 'abcde')                   # => false  # Must be exact.
```

By default, the matching is case-sensitive:

```ruby
File.fnmatch('abc', 'ABC') # => false
```

Case-sensitivity may be modified by flags:

- [`File::FNM_CASEFOLD`](#constant-filefnmcasefold).
- [`File::FNM_SYSCASE`](#constant-filefnmsyscase).

By default, the alternatives pattern is disabled:

```rutby
File.fnmatch('R{ub,foo}y', 'Ruby') # => false
```

It may be enabled by flag [`File::FNM_EXTGLOB`](#constant-filefnmextglob).

By default, the Windows short name pattern is disabled:

```ruby
File.fnmatch('PROGRAM~1', 'Program Files') # => false
```

It may be enabled by flag [`File::FNM_SHORTNAME`](#constant-filefnmshortname).

#### Any Sequence of Characters (`'*'`)

The asterisk pattern (`'*'`) matches any sequence of characters:

```ruby
File.fnmatch('*', 'foo')            # => true
File.fnmatch('*', '')               # => true
File.fnmatch('*', '*')              # => true
File.fnmatch('\*', 'foo')           # => false  # Escaped.
```

By default, the asterisk pattern does not match a leading period (as in a dot-file):

```ruby
File.fnmatch('*', '.document') # => false
```

That matching may be enabled by flag [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch).

By default, the asterisk pattern matches across file separators:

```ruby
File.fnmatch('*.rb', 'lib/test.rb') # => true
```

That matching may be disabled by flag [`File::FNM_PATHNAME`](#constant-filefnmpathname).

#### Single Character (`'?'`)

The question-mark pattern (`'?'`) matches any single character:

```ruby
File.fnmatch('?', 'f')                 # => true
File.fnmatch("foo-?.txt", "foo-1.txt") # => true
File.fnmatch('?', 'foo')               # => false
File.fnmatch('?', '')                  # => false
File.fnmatch('\?', 'f')                # => false  # Escaped.
```

By default, pattern `'?'` matches the file separator:

```ruby
File.fnmatch('foo?boo', 'foo/boo') # => true
```

That matching may be disabled by flag [`File::FNM_PATHNAME`](#constant-filefnmpathname).

#### Single Character from a Set (`'[abc]'`, `'[^abc]'`)

Characters enclosed in square brackets define a set of characters,
any of which matches a single character:

```ruby
File.fnmatch('[ruby]', 'r')      # => true
File.fnmatch('[ruby]', 'u')      # => true
File.fnmatch('[ruby]', 'y')      # => true
File.fnmatch('[ruby]', 'ruby')   # => false
File.fnmatch('\[ruby]', 'r')     # => false  # Escaped.
```

The character set may be negated:

```ruby
File.fnmatch('[^ruby]', 'r') # => false
File.fnmatch('[^ruby]', 'u') # => false
```

#### Single Character from a \Range (`'[a-c]'`, `'[^a-c]'`)

A range of characters enclosed in square brackets defines a set of characters,
any of which matches a single character:

```ruby
File.fnmatch('[a-c]', 'b')           # => true
File.fnmatch('[a-c]', 'd')           # => false
File.fnmatch('[a-c]', 'abc')         # => false
File.fnmatch('R[t-v][a-c]y', 'Ruby') # => true   # Multiple ranges allowed.
File.fnmatch('\[a-c]', 'b')          # => false  # Escaped.
```

The range may be negated:

```ruby
File.fnmatch('[^a-c]', 'b') # => false
File.fnmatch('[^a-c]', 'd') # => true
```

#### Directory-Like Substring (`'**'`)

The double-asterisk pattern (`'**'`) matches any sequence of directory-like substrings;
unless flag [`File::FNM_PATHNAME`](#constant-filefnmpathname) is given,
the pattern is equivalent to pattern `'*'`:

```ruby
File.fnmatch('*', 'a/b/c')                        # => true
File.fnmatch('*', 'a/b/c', File::FNM_PATHNAME)    # => false
File.fnmatch('**/*', 'a/b/c', File::FNM_PATHNAME) # => true
```

#### Escape (`'\'`)

The backslash character (`'\'`) may be used to escape any of the characters
that filename matching treats as special:

```ruby
File.fnmatch('[a-c]', 'b')  # => true
File.fnmatch('\[a-c]', 'b') # => false
File.fnmatch('[a-c\]', 'b') # => false
File.fnmatch('[a\-c]', 'b') # => false

File.fnmatch('{a,b}', 'b', File::FNM_EXTGLOB)  # => true
File.fnmatch('\{a,b}', 'b', File::FNM_EXTGLOB) # => false
File.fnmatch('{a\,b}', 'b', File::FNM_EXTGLOB) # => false
File.fnmatch('{a,b\}', 'b', File::FNM_EXTGLOB) # => false
```

Use a double-backslash to represent an ordinary backslash:

```ruby
File.fnmatch('\\\\', '\\') # => true
```

By default escape pattern `'\'` is enabled;
it may be disabled by flag [`File::FNM_NOESCAPE`](#constant-filefnmnoescape).

### Flags

Optional argument `flags` (defaults to `0`) may be the bitwise OR
of the constants `File::FNM*`.

These are the constants for filename-matching patterns;
see the sections below for details:

| Constant                                            | Meaning                                                     |
|-----------------------------------------------------|-------------------------------------------------------------|
| [`File::FNM_CASEFOLD`](#constant-filefnmcasefold)   | Make the pattern case-insensitive.                          |
| [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch)   | Make pattern `*` match a leading period..                   |
| [`File::FNM_EXTGLOB`](#constant-filefnmextglob)     | Enable alternatives in pattern.                             |
| [`File::FNM_NOESCAPE`](#constant-filefnmnoescape)   | Disable escaping.                                           |
| [`File::FNM_PATHNAME`](#constant-filefnmpathname)   | Make patterns `'*'` and `'?'` not match the file separator. |
| [`File::FNM_SHORTNAME`](#constant-filefnmshortname) | Enable short-name matching (Windows only).                  |
| [`File::FNM_SYSCASE`](#constant-filefnmsyscase)     | Make the pattern use OS's case sensitivity.                 |


#### Constant File::FNM_CASEFOLD

By default, filename matching is case-sensitive;
use constant [`File::FNM_CASEFOLD`](#constant-filefnmcasefold)
to make the matching case-insensitive:

```ruby
File.fnmatch('abc', 'ABC')                     # => false
File.fnmatch('abc', 'ABC', File::FNM_CASEFOLD) # => true
```

#### Constant File::FNM_DOTMATCH

By default, filename matching does not allow pattern `'*'` to match a dotfile name
(i.e, a filename beginning with a dot);
use constant [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch)
to enable the match:

```ruby
File.fnmatch('*', '.document')                     # => false
File.fnmatch('*', '.document', File::FNM_DOTMATCH) # => true
```
#### Constant File::FNM_EXTGLOB

By default, filename matching has the alternative notation disabled;
use constant [`File::FNM_EXTGLOB`](#constant-filefnmextglob)
to enable it:

```ruby
File.fnmatch('R{ub,foo}y', 'Ruby')                    # => false
File.fnmatch('R{ub,foo}y', 'Ruby', File::FNM_EXTGLOB) # => true
```

The alternatives pattern consists of zero or more unquoted strings,
separated by commas, and enclosed in curly braces:

```ruby
File.fnmatch('R{ub,foo,bar}y', 'Ruby')                     # => false  # Not enabled.
File.fnmatch('R{ub,foo,bar}y', 'Ruby', File::FNM_EXTGLOB)  # => true
# Whitespace matters.
File.fnmatch('R{ub ,foo,bar}y', 'Ruby', File::FNM_EXTGLOB) # => false
File.fnmatch('R{ ub,foo,bar}y', 'Ruby', File::FNM_EXTGLOB) # => false
# Special characters remain in force:
File.fnmatch('{*,?}', 'hello', File::FNM_EXTGLOB)          # => true
File.fnmatch('{*ello,?}', 'hello', File::FNM_EXTGLOB)      # => true
File.fnmatch('{*ELLO,?}', 'hello', File::FNM_EXTGLOB)      # => false
File.fnmatch('{*ELLO,?????}', 'hello', File::FNM_EXTGLOB)  # => true
# With the flag not given.
File.fnmatch('R{ub,foo,bar}y', 'Ruby')                     # => false
```

#### Constant File::FNM_NOESCAPE

By default filename matching has escaping enabled;
use constant [`File::FNM_NOESCAPE`](#constant-filefnmnoescape)
to disable it:

```ruby
File.fnmatch('\*\?\*\*', '*?**')                     # => true
File.fnmatch('\*\?\*\*', '*?**', File::FNM_NOESCAPE) # => false
```

#### Constant File::FNM_PATHNAME

By default, filename matching enables patterns `'*'` and `'?'` to match
at or across the file separator (`File::SEPARATOR`);
use constant [`File::FNM_PATHNAME`](#constant-filefnmpathname)
to disable such matching:

```ruby
File::SEPARATOR                                          # => "/"
File.fnmatch('*.rb', 'lib/test.rb')                      # => true
File.fnmatch('*.rb', 'lib/test.rb', File::FNM_PATHNAME)  # => false
File.fnmatch('foo?boo', 'foo/boo')                       # => true
File.fnmatch('foo?boo', 'foo/boo', File::FNM_PATHNAME)   # => false
```

#### Constant File::FNM_SHORTNAME

By default, Windows shortname matching is disabled;
use constant [`File::FNM_SHORTNAME`](#constant-filefnmshortname)
to enable it (on Windows only).

Using that constant allows patterns to match short names
in filename matching on Windows,
which can be useful for compatibility with legacy applications
that rely on these short names;
see [8.3 filename](https://en.wikipedia.org/wiki/8.3_filename).
This feature helps ensure that file operations work correctly
even when dealing with files that have long names.

```ruby
File::FNM_SHORTNAME.zero? # => false  # On Windows, not zero; may be enabled.
File::FNM_SHORTNAME.zero? # => true   # Elsewhere, always zero; may not be enabled.

File.fnmatch('PROGRAM~1', 'Program Files') # => false
# This will be true if and only if on Windows and short name 'PROGRAM~1' exists.
File.fnmatch('PROGRAM~1', 'Program Files', File::FNM_SHORTNAME) # => true
```

#### Constant File::FNM_SYSCASE

By default, filename matching uses Ruby's own case-sensitivity rules;
use constant [`File::FNM_SYSCASE`](#constant-filefnmsyscase)
to use the case-sensitivity rules of the underlying file system:

```ruby
File::FNM_SYSCASE.zero? # => false  # On Windows, not zero; may be enabled.
File::FNM_SYSCASE.zero? # => true   # Elsewhere, always zero; may not be enabled.

File.fnmatch('abc', 'ABC')                    # => false  # Ruby; case-sensitive.
File.fnmatch('abc', 'ABC', File::FNM_SYSCASE) # => true   # Windows; case-insensitive.
File.fnmatch('abc', 'ABC', File::FNM_SYSCASE) # => false  # Linus; case-sensitive.
```

