## Filename Globbing

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

### Patterns

#### Simple \String

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


#### Any Sequence of Characters (`'*'`)

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

#### Single Character (`'?'`)

The question-mark pattern (`'?'`) matches any single character:

```ruby
Dir.glob('???') # => ["GPL", "bin", "doc", "enc", "ext", "jit", "lib", "man"]
Dir.glob('??')  # => ["gc"]  # Only one entry with a 2-character name.
Dir.glob('?')   # => []      # No entries with a 1-character name.
Dir.glob('\?')  # => []      # No entries containing character '?'.
```


#### Single Character from a Set (`'[abc]'`, `'[^abc]'`)

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

### Keyword Argument `flags`


### Keyword Argument `base`


### Keyword Argument `sort`
