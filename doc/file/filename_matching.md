## Filename Globbing

Filename globbing is a pattern-matching feature implemented in certain Ruby methods.

Each `fnmatch` method matches a pattern against a string _path_;
these methods operate only on strings, and do not access the file system:

- File.fnmatch.
- Pathname#fnmatch.

Each `glob` method matches a pattern against string paths found in the actual file system;

- Dir.glob.
- Pathname.glob.
- Pathname#glob.



### Patterns

These are the basic elements of patterns;
see the sections below for details:

| Pattern  | Meaning                                    | Examples         |
|:--------:|--------------------------------------------|------------------|
|   `*`    | Matches any sequence of characters.        | `*.txt`          |
|   `?`    | Matches any single character.              | `?.txt`          |
| `[abc]`  | Matches a single character from a set.     | `file[12].txt`   |
| `[a-z]`  | Matches a single character from a range.   | `image[0-9].png` |
| `[^a-z]` | Matches a single character not in a range. | `[^0-9]`         |
| `{ , }`  | Alternatives (with `File::FNM_EXTGLOB`)    | `{ab,cd}`        |
|   `**`   | Recursive directory matching.              | `lib/**/*.rb`    |
|  `\`     | Escape.                                    | `\*`, `\?`       |

#### Sequence of Characters

The asterisk character (`'*'`) matches any sequence of characters:

```ruby
File.fnmatch('*', 'foo')  # => true
File.fnmatch('*', '')     # => true
File.fnmatch('*', '*')    # => true
File.fnmatch('\*', 'foo') # => false  # Escaped.
```

#### Single Character

The question-mark character (`'>'`) matches any single character:

```ruby
File.fnmatch('?', 'f')     # => true
File.fnmatch('?*', 'foo')  # => true
File.fnmatch('*?*', 'foo') # => true
File.fnmatch('*?', 'foo')  # => true
File.fnmatch('?', 'foo')   # => false
File.fnmatch('?', '')      # => false
File.fnmatch('\?', 'f')    # => false  # Escaped.
```

#### Single Character from a Set

Characters enclosed in square brackets define a set of characters,
any of which matches a single character:

```ruby
File.fnmatch('[ruby]', 'r')      # => true
File.fnmatch('[ruby]', 'u')      # => true
File.fnmatch('[ruby]', 'y')      # => true
File.fnmatch('[ruby]', 'ruby')   # => false
File.fnmatch('*[ruby]', 'ruby')  # => true
File.fnmatch('[ruby]*', 'ruby')  # => true
File.fnmatch('*[ruby]*', 'ruby') # => true
File.fnmatch('\[ruby]', 'r')     # => false  # Escaped.
```

#### Single Character from a Range

A range of characters enclosed in square brackets defines a set of characters,
any of which matches a single character:

```ruby
File.fnmatch('[a-c]', 'b')      # => true
File.fnmatch('[a-c]', 'd')      # => false
File.fnmatch('[a-c]', 'abc')    # => false
File.fnmatch('*[a-c]', 'abc')   # => true
File.fnmatch('[a-c]*', 'abc')   # => true
File.fnmatch('*[a-c]*', 'abc')  # => true
File.fnmatch('[a-c][x-z]', 'b') # => false  # Only one range allowed.
File.fnmatch('\[a-c]', 'b')     # => false  # Escaped.
```

#### Alternatives

Flag File::FNM_EXTGLOB enables the alternatives pattern;
the pattern consists of zero or more unquoted strings,
separated by commas, and enclosed in curly brackets:

```ruby
File.fnmatch('R{ub,foo,bar}y', 'Ruby', File::FNM_EXTGLOB)  # => true
File.fnmatch('R{foo,ub,bar}y', 'Ruby', File::FNM_EXTGLOB)  # => true
File.fnmatch('R{foo,bar,ub}y', 'Ruby', File::FNM_EXTGLOB)  # => true
File.fnmatch('R{ub,foo,bar}y', 'Ruby', File::FNM_EXTGLOB)  # => true
# Also valid, but probably not useful.
File.fnmatch('R{foo,ub,bar}y', 'Ruby', File::FNM_EXTGLOB)  # => true
File.fnmatch('R{foo,bar,ub}y', 'Ruby', File::FNM_EXTGLOB)  # => true
# Whitespace matters.
File.fnmatch('R{ub ,foo,bar}y', 'Ruby', File::FNM_EXTGLOB) # => false
File.fnmatch('R{ ub,foo,bar}y', 'Ruby', File::FNM_EXTGLOB) # => false
# All characters are treated as just ordinary characters:
File.fnmatch('{*,?}', '?', File::FNM_EXTGLOB)              # => true
File.fnmatch('{*,?}', '*', File::FNM_EXTGLOB)              # => true
# With the flag not given.
File.fnmatch('R{ub,foo,bar}y', 'Ruby')                     # => false
```

#### Recursive Directory Matching

The double-asterisk notation (`'**'`) matches any sequence of directory-like substrings:

```ruby
target = 'a/b/c/d/e/t.rb'
File.fnmatch('**/t.rb', target)           # => true   # '**' matches 'a/b/c/d/e'
File.fnmatch('a/**/t.rb', target)         # => true   # '**' matches 'b/c/d/e'
File.fnmatch('a/b/**/t.rb', target)       # => true   # '**' matches 'c/d/e'
File.fnmatch('a/b/c/d/e/**/t.rb', target) # => false
```

#### Escaping



### Flags


