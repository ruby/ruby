# Filename Globbing

Filename globbing is a pattern-matching feature implemented in certain Ruby methods.

Filename-globbing methods find filesystem entries (files and directories)
that match certain patterns;
these methods are:

- Dir.glob.
- [`Dir[]`](https://docs.ruby-lang.org/en/master/Dir.html#method-c-5B-5D).
- Pathname.glob.
- Pathname#glob.

These methods are quite different from filename-matching methods (not discussed here),
which match patterns against string paths, and do not access the filesystem;
those methods are:

- File.fnmatch.
- Pathname#fnmatch.

These are the basic elements of filename-globbing patterns;
see the sections below for details:

|         Pattern          | Meaning                                  | Examples                     |
|:------------------------:|------------------------------------------|------------------------------|
|      Simple string.      | Matches itself.                          | `'LEGAL'`                    |
|          `'*'`           | Matches any sequence of characters.      | `'*.txt'`                    |
|          `'?'`           | Matches any single character.            | `'?.txt'`                    |
| `'[abc]'`,<br>`'[^abc]'` | Matches a single character from a set.   | `'x[abc]y'`,<br>`'x[^abc]y'` |
| `'[a-z]`',<br>`'[^a-z]'` | Matches a single character from a range. | `'x[0-9]y'`,<br>`'x[^0-9]y'` |
|        `'{ , }'`         | Matches alternatives.                    | `'{abc,def}'`                |
|          `'**'`          | Matches directories recursively.         | `'**/test.rb'`               |
|          `'\'`           | Escapes the next character.              | `'\\*'`, `'\?'`              |

## Patterns

### Simple \String

A "simple string" is one that does not contain special filename-globbing patterns;
see the table above.

A simple string matches itself:

```ruby
Dir.glob('LEGAL') # => ["LEGAL"]
Dir.glob('LEGA')  # => []  # Must be exact.
Dir.glob('legal') # => []  # Case-sensitive.
```

Note that case-sensitivity may _not_ be modified by flags.

By default, the Windows short name pattern is disabled:

```ruby
Dir.glob('PROGRAM~1') # => []
```

It may be enabled by flag [`File::FNM_SHORTNAME`](#constant-filefnmshortname).


### Any Sequence of Characters (`'*'`)

The asterisk pattern (`'*'`) matches any sequence of characters:

```ruby
Dir.glob('*').take(3) # => ["BSDL", "CONTRIBUTING.md", "COPYING"]
Dir.glob('\*')        # => []  # Escaped.
```

By default, the asterisk pattern does not match a leading period (as in a dot-file):

```ruby
Dir.glob('*').select {|entry| entry.start_with?('.') } # => []
```

That matching may be enabled by flag [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch).

The asterisk pattern does not match across file separators:

```ruby
Dir.glob('*.rb').select {|entry| entry.include?('/') } # => []
```

Therefore flag File::FNM_PATHNAME does not affect the pattern.

### Single Character (`'?'`)

The question-mark pattern (`'?'`) matches any single character:

```ruby
Dir.glob('???') # => ["GPL", "bin", "doc", "enc", "ext", "jit", "lib", "man"]
Dir.glob('??')  # => ["gc"]  # Only one entry with a 2-character name.
Dir.glob('?')   # => []      # No entries with a 1-character name.
Dir.glob('\?')  # => []      # No entries containing character '?'.
```

By default, the question-mark pattern does not match a leading period (as in a dot-file):

```ruby
Dir.glob(".???") # => [".git"]
Dir.glob("????").select {|entry| entry.start_with?('.') } # => []
```

That matching may be enabled by flag [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch).

### Single Character from a Set (`'[abc]'`, `'[^abc]'`)

Characters enclosed in square brackets define a set of characters,
any of which matches a single character:

```ruby
Dir.glob('[efgh][abcd]')  # => ["gc"]
Dir.glob('\[efgh][abcd]') # => []  # Escaped.
```

The character set may be negated:

```ruby
Dir.glob('[^abcd][^efgh]') # => ["gc"]
```

### Single Character from a \Range (`'[a-c]'`, `'[^a-c]'`)

A range of characters enclosed in square brackets defines a set of characters,
any of which matches a single character:

```ruby
Dir.glob('[k-m][h-j][a-c]')  # => ["lib"]
Dir.glob('\[k-m][h-j][a-c]') # => []  # Escaped.
```

The range may be negated:

```ruby
Dir.glob('[^k-m][h-j][a-c]')  # => []
Dir.glob('[^a-c][^k-m][^h-j]') # => ["GPL", "doc", "enc", "ext", "jit", "lib", "man"]
```

### Alternatives (`'{ , }'`)

The alternatives pattern consists of comma-separated strings
enclosed in curly braces:

```ruby
Dir.glob('{k,L,R}*')  # => ["kernel.rb", "LEGAL", "README.ja.md", "README.md"]
Dir.glob('{R,L,k}*')  # => ["README.ja.md", "README.md", "LEGAL", "kernel.rb"]
# Whitespace matters:
Dir.glob('{k ,L,R}*') # => ["LEGAL", "README.ja.md", "README.md"]
```

### Recursive Directory Matching (`'**'`)

The double-asterisk pattern (`'**'`) matches directories recursively:

```ruby
# Find all entries everywhere ending with '.ja'.
Dir.glob('**/*.ja')
# => ["COPYING.ja", "doc/pty/README.expect.ja", "doc/pty/README.ja"]

# Find all entries everywhere ending with '.rb'.
Dir.glob('**/*.rb').size    # => 7574
Dir.glob('**/*.rb').take(3)
# => ["KNOWNBUGS.rb", "array.rb", "ast.rb"]

# Find all entries in directory 'lib' ending with `.rb'.
Dir.glob('lib/**/*.rb').size # => 626
Dir.glob('lib/**/*.rb').take(3)
# # =>
# ["lib/English.rb",
#  "lib/bundled_gems.rb",
#  "lib/bundler/build_metadata.rb"]

# Find all entries in directory 'test/ruby' ending with '.rb'.
Dir.glob('test/ruby/**/*.rb').size # => 200
Dir.glob('test/ruby/**/*.rb').take(3)
# # =>
# ["test/ruby/allpairs.rb",
#  "test/ruby/beginmainend.rb",
#  "test/ruby/box/a.1_1_0.rb"]

# Escaped.
Dir.glob('\**/*.rb') # => []
```


### Escape (`'\'`)

The backslash character (`'\'`) may be used to escape any of the characters
that filename globbing treats as special:

```ruby
Dir.glob('\*')               # => []
Dir.glob('\?')               # => []
Dir.glob('\[efgh][abcd]')    # => []
Dir.glob('\[k-m][h-j][a-c]') # => []
Dir.glob('\**/*.rb')         # => []
```

## Keyword Arguments

| Keyword           | Value                    | Default | Meaning                                 |
|-------------------|--------------------------|:-------:|-----------------------------------------|
| [`base`](#base)   | \String path.            |  `'.'`  | Root for searching.                     |
| [`flags`](#flags) | Logical OR of constants. |   `0`   | Modify globbing behavior.               |
| [`sort`](#sort)   | `true` or `false`        | `true`  | Whether returned array is to be sorted. |

### `base`

Optional keyword argument `base` (defaults to `'.'`)
specifies where in the filesystem the searching is to begin:

```ruby
Dir.glob('*').size                  # => 241
Dir.glob('*').take(3)
# => ["BSDL", "CONTRIBUTING.md", "COPYING"]

Dir.glob('*', base: 'lib').size     # => 72
Dir.glob('*', base: 'lib').take(3)
# => ["English.gemspec", "English.rb", "bundled_gems.rb"]

Dir.glob('*', base: 'lib/net').size # => 5
Dir.glob('*', base: 'lib/net').take(3)
# => ["http", "http.rb", "https.rb"]
```

### `flags`

Optional keyword argument `flags` (defaults to `0`) may be the bitwise OR
of the constants `File::FNM*`:

```ruby
Dir.glob('*', flags: File::FNM_DOTMATCH | File::FNM_NOESCAPE)
```

These are the constants for filename-globbing patterns;
see the sections below for details:


| Constant                                            | Meaning                                    |
|-----------------------------------------------------|--------------------------------------------|
| [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch)   | Make pattern `'*'` match a leading period. |
| [`File::FNM_NOESCAPE`](#constant-filefnmnoescape)   | Disable escaping.                          |
| [`File::FNM_SHORTNAME`](#constant-filefnmshortname) | Enable short-name matching (Windows only). |

These constants do not affect filename globbing:

- File::FNM_CASEFOLD.
- File::FNM_EXTGLOB.
- File::FNM_PATHNAME.
- File::FNM_SYSCASE.

#### Constant File::FNM_DOTMATCH

By default, filename globbing does not allow patterns `'*'` and `'?'` to match a dotfile name
(i.e, an entry name beginning with a dot);
use constant [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch)
to enable the match:

```ruby
Dir.glob('*').size                               # => 241
Dir.glob('*', flags: File::FNM_DOTMATCH).size    # => 256
Dir.glob('*', flags: File::FNM_DOTMATCH).take(3) # => [".", ".dir-locals.el", ".document"]
```

#### Constant File::FNM_NOESCAPE

By default filename globbing has escaping enabled;
use constant [`File::FNM_NOESCAPE`](#constant-filefnmnoescape)
to disable it:

```ruby
Dir.glob('*').size  # => 241
Dir.glob('\*').size # => 0
```

#### Constant File::FNM_SHORTNAME

By default, Windows shortname matching is disabled;
use constant [`File::FNM_SHORTNAME`](#constant-filefnmshortname)
to enable it (on Windows only).

Using that constant allows patterns to match short names
in filename globbing on Windows,
which can be useful for compatibility with legacy applications
that rely on these short names;
see [8.3 filename](https://en.wikipedia.org/wiki/8.3_filename).
This feature helps ensure that file operations work correctly
even when dealing with files that have long names.

### `sort`

Optional keyword argument `sort` (defaults to `'true'`)
specifies whether the returned array is to be sorted:

```ruby
Dir.glob('*').take(3)
# => ["BSDL", "CONTRIBUTING.md", "COPYING"]
Dir.glob('*', sort: false).take(3)
# => ["gc.rb", "yjit.rb", "iseq.h"]
```

