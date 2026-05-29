## Filename Globbing

Filename globbing is a pattern-matching feature implemented in certain Ruby methods:

- Dir.glob.
- File.fnmatch.
- Pathname#fnmatch.
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



#### Recursive Directory Matching



#### Escape
