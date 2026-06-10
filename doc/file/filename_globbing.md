# Filename Globbing

Filename globbing is a pattern-matching feature implemented in certain Ruby methods:

- Dir.glob.
- Pathname#glob.
- [`Dir[]`](https://docs.ruby-lang.org/en/master/Dir.html#method-c-5B-5D),
  which is like Dir.glob except that it does not accept keyword argument `flags`.

Each `glob` method selects filesystem entries (file and directory names)
that match certain patterns,
under the control of keyword arguments `base` and `flags`;
the selected entries may be sorted, according to keyword argument `sort`.

These filename-globbing methods are quite different
from [filename-matching](rdoc-ref:filename_matching.md) methods,
which match patterns against string paths, and do not access the filesystem.

Inputs to the filename-globbing methods:

- The argument `patterns` is a string or an array of strings,
  which are _not_ Regexp objects;
  see [Patterns](#patterns).
- Keyword argument `base` specifies the entry in the filesystem where searching is to begin;
  see [base](#base).
- Keyword argument `flags` specifies an integer value that may be defined by constants;
  see [flags](#flags).
  This argument is not available
  in method [`Dir[]`](https://docs.ruby-lang.org/en/master/Dir.html#method-c-5B-5D),
  for which the flags value is zero.
- Keyword argument `sort` specifies whether the returned array is to be sorted.
  see [sort](#sort).

Their return values:

- Each of the methods `Dir[]` and Dir.glob returns an array of the selected string entries.
- \Method Pathname#glob with no block returns an array of Pathname objects
  each based on a selected string entry.
- \Method Pathname#glob with a block calls the block with each pathname
  based on a selected string entry.

Examples:

```ruby
Dir['*'].take(3)
# => ["BSDL", "CONTRIBUTING.md", "COPYING"]
Dir.glob('*').take(3)
# => ["BSDL", "CONTRIBUTING.md", "COPYING"]
Pathname('.').glob('*').take(3)
# => [#<Pathname:BSDL>, #<Pathname:CONTRIBUTING.md>, #<Pathname:COPYING>]
a = []
Pathname('.').glob('*') {|pn| a << pn if pn.to_s.end_with?('.c') } # => nil
a.take(3) # => [#<Pathname:addr2line.c>, #<Pathname:array.c>, #<Pathname:ast.c>]
```

The examples below for Pathname#glob do not give blocks.

## Patterns

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
Dir.glob('LEGAL')           # => ["LEGAL"]
Dir.glob('LEGA')            # => []  # Must be exact.
Dir.glob('legal')           # => []  # Case-sensitive.
Pathname('.').glob('LEGAL') # => [#<Pathname:LEGAL>]
Pathname('.').glob('LEGA')  # => []  # Must be exact.
Pathname('.').glob('legal') # => []  # Case-sensitive.
```

Note that case-sensitivity may _not_ be modified by flags.

By default, the Windows short name pattern is disabled:

```ruby
Dir.glob('PROGRAM~1')           # => []
Pathname('.').glob('PROGRAM~1') # => []
```

It may be enabled by flag [`File::FNM_SHORTNAME`](#constant-filefnmshortname).

### Any Sequence of Characters (`'*'`)

The asterisk pattern (`'*'`) matches any sequence of characters:

```ruby
Dir.glob('*').take(3) # => ["BSDL", "CONTRIBUTING.md", "COPYING"]
Pathname('.').glob('*').take(3)
# =>
# #<Pathname:BSDL>,
#     #<Pathname:CONTRIBUTING.md>,
#     #<Pathname:COPYING>]
```

The pattern may be escaped:

```ruby
Dir.glob('\*')           # => []
Pathname('.').glob('\*') # => []
```

By default, the asterisk pattern does not match a leading period (as in a dot-file):

```ruby
Dir.glob('*').select {|entry| entry.start_with?('.') }           # => []
Pathname('.').glob('*') .select {|pn| pn.to_s.start_with?('.') } # => []
```

That matching may be enabled by flag [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch).

The asterisk pattern does not match across file separators:

```ruby
Dir.glob('*.rb').select {|entry| entry.include?('/') }           # => []
Pathname('.').glob('*.rb') .select {|pn| pn.to_s.include?('/') } # => []
```

Therefore flag File::FNM_PATHNAME does not affect the pattern.

### Single Character (`'?'`)

The question-mark pattern (`'?'`) matches any single character:

```ruby
Dir.glob('???') # => ["GPL", "bin", "doc", "enc", "ext", "jit", "lib", "man"]
Dir.glob('??')  # => ["gc"]                     # Only one entry with a 2-character name.
Dir.glob('?')   # => []                         # No entries with a 1-character name.
Dir.glob('\?')  # => []                         # No entries containing character '?'.
Pathname('.').glob('???').take(3) # => [#<Pathname:GPL>, #<Pathname:bin>, #<Pathname:doc>]
Pathname('.').glob('??') # => [#<Pathname:gc>]  # Only one entry with a 2-character name.
Pathname('.').glob('?')  # => []                # No entries with a 1-character name.
Pathname('.').glob('\?') # => []                # No entries containing character '?'.
```

By default, the question-mark pattern does not match a leading period (as in a dot-file):

```ruby
Dir.glob(".???")                                                   # => [".git"]
Dir.glob("????").select {|entry| entry.start_with?('.') }          # => []
Pathname('.').glob('.???')                                         # => [#<Pathname:.git>]
Pathname('.').glob('????').select {|pn| pn.to_s.start_with?('.') } # => []
```

That matching may be enabled by flag [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch).

### Single Character from a Set (`'[abc]'`, `'[^abc]'`)

Characters enclosed in square brackets define a set of characters,
any of which matches a single character:

```ruby
Dir.glob('[efgh][abcd]')           # => ["gc"]
Pathname('.').glob('[efgh][abcd]') # => [#<Pathname:gc>]
```

The pattern may be escaped:

```ruby
Dir.glob('\[efgh][abcd]')           # => []
Pathname('.').glob('\[efgh][abcd]') # => []
```

The character set may be negated:

```ruby
Dir.glob('[^abcd][^efgh]')           # => ["gc"]
Pathname('.').glob('[^abcd][^efgh]') # => [#<Pathname:gc>]
```

### Single Character from a \Range (`'[a-c]'`, `'[^a-c]'`)

A range of characters enclosed in square brackets defines a set of characters,
any of which matches a single character:

```ruby
Dir.glob('[k-m][h-j][a-c]')           # => ["lib"]
Pathname('.').glob('[k-m][h-j][a-c]') # => [#<Pathname:lib>]
```

The pattern may be escaped:

```ruby
Dir.glob('\[k-m][h-j][a-c]')           # => []
Pathname('.').glob('\[k-m][h-j][a-c]') # => []
```

The range may be negated:

```ruby
Dir.glob('[^k-m][h-j][a-c]')           # => []
Dir.glob('[^a-c][^k-m][^h-j]').take(3) # => ["GPL", "doc", "enc"]
Pathname('.').glob('[^k-m][h-j][a-c]') # => []
Pathname('.').glob('[^a-c][^k-m][^h-j]').take(3)
# => [#<Pathname:GPL>, #<Pathname:doc>, #<Pathname:enc>]

```

### Alternatives (`'{ , }'`)

The alternatives pattern consists of comma-separated strings
enclosed in curly braces:

```ruby
Dir.glob('{k,L,R}*').take(3)  # => ["kernel.rb", "LEGAL", "README.ja.md"]
Dir.glob('{R,L,k}*').take(3)  # => ["README.ja.md", "README.md", "LEGAL"]
Pathname('.').glob('{k,L,R}*').take(3)
# # =>
# [#<Pathname:kernel.rb>,
#     #<Pathname:LEGAL>,
#     #<Pathname:README.ja.md>]
Pathname('.').glob('{R,L,k}*').take(3)
# # =>
# [#<Pathname:README.ja.md>,
#     #<Pathname:README.md>,
#     #<Pathname:LEGAL>]
```

Whitespace matters:

```ruby
Dir.glob('{k ,L,R}*') # => ["LEGAL", "README.ja.md", "README.md"]
Pathname('.').glob('{k ,L,R}*')
# # =>
# [#<Pathname:LEGAL>,
#     #<Pathname:README.ja.md>,
#     #<Pathname:README.md>]
```

### Recursive Directory Matching (`'**'`)

The double-asterisk pattern (`'**'`) matches directories recursively:

```ruby
# Find all entries everywhere ending with '.ja'.
Dir.glob('**/*.ja') # => ["COPYING.ja", "doc/pty/README.expect.ja", "doc/pty/README.ja"]
Pathname('.').glob('**/*.ja')
# # =>
# [#<Pathname:COPYING.ja>,
#     #<Pathname:doc/pty/README.expect.ja>,
#     #<Pathname:doc/pty/README.ja>]

# Find all entries everywhere ending with '.rb'.
Dir.glob('**/*.rb').size           # => 7527
Dir.glob('**/*.rb').take(3)        # => ["KNOWNBUGS.rb", "array.rb", "ast.rb"]
Pathname('.').glob('**/*.rb').size # => 7527
Pathname('.').glob('**/*.rb').take(3)
# # =>
# [#<Pathname:KNOWNBUGS.rb>,
#     #<Pathname:array.rb>,
#     #<Pathname:ast.rb>]

# Find all entries in directory 'lib' ending with `.rb'.
Dir.glob('lib/**/*.rb').size           # => 621
Dir.glob('lib/**/*.rb').take(3)
# # =>
# ["lib/English.rb",
#  "lib/bundled_gems.rb",
#  "lib/bundler/build_metadata.rb"]
Pathname('.').glob('lib/**/*.rb').size # => 621
Pathname('.').glob('lib/**/*.rb').take(3)
# # =>
# [#<Pathname:lib/English.rb>,
#     #<Pathname:lib/bundled_gems.rb>,
#     #<Pathname:lib/bundler/build_metadata.rb>]

# Find all entries in directory 'test/ruby' ending with '.rb'.
Dir.glob('test/ruby/**/*.rb').size           # => 200
Dir.glob('test/ruby/**/*.rb').take(3)
# # =>
# ["test/ruby/allpairs.rb",
#  "test/ruby/beginmainend.rb",
#  "test/ruby/box/a.1_1_0.rb"]
Pathname('.').glob('test/ruby/**/*.rb').size # => 200
Pathname('.').glob('test/ruby/**/*.rb').take(3)
# # =>
# [#<Pathname:test/ruby/allpairs.rb>,
#     #<Pathname:test/ruby/beginmainend.rb>,
#     #<Pathname:test/ruby/box/a.1_1_0.rb>]
```

The pattern may be escaped:

```ruby
Dir.glob('\**/*.rb')           # => []
Pathname('.').glob('\**/*.rb') # => []
```


### Escape (`'\'`)

The backslash character (`'\'`) may be used to escape any of the characters
that filename globbing treats as special:

```ruby
Dir.glob('\*')                         # => []
Dir.glob('\?')                         # => []
Dir.glob('\[efgh][abcd]')              # => []
Dir.glob('\[k-m][h-j][a-c]')           # => []
Dir.glob('\**/*.rb')                   # => []
Pathname('.').glob('\*')               # => []
Pathname('.').glob('\?')               # => []
Pathname('.').glob('\[efgh][abcd]')    # => []
Pathname('.').glob('\[k-m][h-j][a-c]') # => []
Pathname('.').glob('\**/*.rb')         # => []
```

## Keyword Arguments

| Keyword           | Value                    | Default | Meaning                                 |
|-------------------|--------------------------|:-------:|-----------------------------------------|
| [`base`](#base)   | \String path.            |  `'.'`  | Root for searching.                     |
| [`flags`](#flags) | Logical OR of constants. |   `0`   | Modify globbing behavior.               |
| [`sort`](#sort)   | `true` or `false`        | `true`  | Whether returned array is to be sorted. |

### `base`

Optional keyword argument `base` (defaults to `'.'`)
specifies (for `Dir.glob`) where in the filesystem the searching is to begin;
the argument is ignored for `Pathname#glob`, whose "base" is its string path:

```ruby
# Default base '.'.
Dir.glob('*').take(3)
# => ["BSDL", "CONTRIBUTING.md", "COPYING"]
Dir.glob('*', base: 'lib').take(3)
# => ["English.gemspec", "English.rb", "bundled_gems.rb"]
Dir.glob('*', base: 'lib/net').take(3)
# => ["http", "http.rb", "https.rb"]
Pathname('.').glob('*').take(3)
# => [#<Pathname:BSDL>, #<Pathname:CONTRIBUTING.md>, #<Pathname:COPYING>]
Pathname('lib').glob('*').take(3)
# => [#<Pathname:lib/English.gemspec>, #<Pathname:lib/English.rb>, #<Pathname:lib/bundled_gems.rb>]
Pathname('lib/net').glob('*').take(3)
# => [#<Pathname:lib/net/http>, #<Pathname:lib/net/http.rb>, #<Pathname:lib/net/https.rb>]
```

Note that the base directory is not prepended to the entry names in the result.

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

By default, filename globbing does not allow patterns `'*'` and `'?'`
to match a dotfile name
(i.e, an entry name beginning with a dot);
use constant [`File::FNM_DOTMATCH`](#constant-filefnmdotmatch)
to enable the match:

```ruby
Dir.glob('*').size                                      # => 241
Dir.glob('*', flags: File::FNM_DOTMATCH).size           # => 256
Dir.glob('*', flags: File::FNM_DOTMATCH).take(3)
# => [".", ".dir-locals.el", ".document"]
Pathname('.').glob('*').size                            # => 241
Pathname('.').glob('*', flags: File::FNM_DOTMATCH).size # => 256
Pathname('.').glob('*', flags: File::FNM_DOTMATCH).take(3)
# => [#<Pathname:.>, #<Pathname:.dir-locals.el>, #<Pathname:.document>]
```

#### Constant File::FNM_NOESCAPE

By default filename globbing has escaping enabled;
use constant [`File::FNM_NOESCAPE`](#constant-filefnmnoescape)
to disable it:

```ruby
Dir.glob('*').size                                # => 241
Dir.glob('\*').size                               # => 0
Dir.glob('\*', File::FNM_NOESCAPE).size           # => 0
Pathname('.').glob('*').size                      # => 241
Pathname('.').glob('\*').size                     # => 0
Pathname('.').glob('\*', File::FNM_NOESCAPE).size # => 0
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
Dir.glob('*').take(3)              # => ["BSDL", "CONTRIBUTING.md", "COPYING"]
Dir.glob('*', sort: false).take(3) # => ["gc.rb", "yjit.rb", "iseq.h"]
Pathname('.').glob('*').take(3)
# => [#<Pathname:BSDL>, #<Pathname:CONTRIBUTING.md>, #<Pathname:COPYING>]
Pathname('.').glob('*', sort: false).take(3)
# => [#<Pathname:gc.rb>, #<Pathname:yjit.rb>, #<Pathname:iseq.h>]
```

