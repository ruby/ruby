# Pre-Defined Global Variables

Some of the pre-defined global variables have synonyms
that are available via module English.
For each of those, the \English synonym is given.

To use the module:

```ruby
require 'English'
```

## Summary

### Exceptions

| Variable    | English           | Contains                                           |
|-------------|-------------------|----------------------------------------------------|
| `$!`        | `$ERROR_INFO`     | Exception object; set by Kernel#raise.             |
| `$@`        | `$ERROR_POSITION` | Array of backtrace positions; set by Kernel#raise. |

### Pattern Matching

| Variable      | English             | Contains                                         |
|---------------|---------------------|--------------------------------------------------|
| `$~`          | `$LAST_MATCH_INFO`  | MatchData object; set by matcher method.         |
| `$&`          | `$MATCH`            | Matched substring; set by matcher method.        |
| `` $` ``      | `$PRE_MATCH`        | Substring left of match; set by matcher method.  |
| `$'`          | `$POST_MATCH`       | Substring right of match; set by matcher method. |
| `$+`          | `$LAST_PAREN_MATCH` | Last group matched; set by matcher method.       |
| `$1`          |                     | First group matched; set by matcher method.      |
| `$2`          |                     | Second group matched; set by matcher method.     |
| <tt>$_n_</tt> |                     | <i>n</i>th group matched; set by matcher method. |

### Separators

| Variable | English                    | Contains                                   |
|----------|----------------------------|--------------------------------------------|
| `$/`     | `$INPUT_RECORD_SEPARATOR`  | Input record separator; initially newline. |
| `$\`     | `$OUTPUT_RECORD_SEPARATOR` | Output record separator; initially `nil`.  |

### Streams

| Variable  | English                     | Contains                                      |
|-----------|-----------------------------|-----------------------------------------------|
| `$stdin`  |                             | Standard input stream; initially `STDIN`.     |
| `$stdout` |                             | Standard input stream; initially `STDIOUT`.   |
| `$stderr` |                             | Standard input stream; initially `STDERR`.    |
| `$<`      | `$DEFAULT_INPUT`            | Default standard input; `ARGF` or `$stdin`.   |
| `$>`      | `$DEFAULT_OUTPUT`           | Default standard output; initially `$stdout`. |
| `$.`      | `$INPUT_LINE_NUMBER`, `$NR` | Input position of most recently read stream.  |
| `$_`      | `$LAST_READ_LINE`           | String from most recently read stream.        |

### Processes

| Variable                  | English               | Contains                                               |
|---------------------------|-----------------------|--------------------------------------------------------|
| `$0`                      |                       | Initially, the name of the executing program.          |
| `$*`                      | `$ARGV`               | Points to the `ARGV` array.                            |
| `$$`                      | `$PROCESS_ID`, `$PID` | Process ID of the current process.                     |
| `$?`                      | `$CHILD_STATUS`       | Process::Status of most recently exited child process. |
| `$LOAD_PATH`, `$:`, `$-I` |                       | Array of paths to be searched.                         |
| `$LOADED_FEATURES`, `$"`  |                       | Array of paths to loaded files.                        |

### Debugging

| Variable    | English | Contains                                               |
|-------------|---------|--------------------------------------------------------|
| `$FILENAME` |         | The value returned by method ARGF.filename.            |
| `$DEBUG`    |         | Initially, whether option `-d` or `--debug` was given. |
| `$VERBOSE`  |         | Initially, whether option `-V` or `-W` was given.      |

### Other Variables

| Variable | English | Contains                                       |
|----------|---------|------------------------------------------------|
| `$-a`    |         | Whether option `-a` was given.                 |
| `$-i`    |         | Extension given with command-line option `-i`. |
| `$-l`    |         | Whether option `-l` was given.                 |
| `$-p`    |         | Whether option `-p` was given.                 |

## Exceptions

### `$!` (\Exception)

Contains the Exception object set by Kernel#raise:

```ruby
begin
  raise RuntimeError.new('Boo!')
rescue RuntimeError
  p $!
end
```

Output:

```
#<RuntimeError: Boo!>
```

English - `$ERROR_INFO`

### `$@` (Backtrace)

Same as `$!.backtrace`;
returns an array of backtrace positions:

```ruby
begin
  raise RuntimeError.new('Boo!')
rescue RuntimeError
  pp $@.take(4)
end
```

Output:

```
["(irb):338:in `<top (required)>'",
 "/snap/ruby/317/lib/ruby/3.2.0/irb/workspace.rb:119:in `eval'",
 "/snap/ruby/317/lib/ruby/3.2.0/irb/workspace.rb:119:in `evaluate'",
 "/snap/ruby/317/lib/ruby/3.2.0/irb/context.rb:502:in `evaluate'"]
```

English - `$ERROR_POSITION`.

## Pattern Matching

These global variables store information about the most recent
successful match in the current scope.

For details and examples,
see {Regexp Global Variables}[rdoc-ref:Regexp@Global+Variables].

### `$~` (\MatchData)

MatchData object created from the match;
thread-local and frame-local.

English - `$LAST_MATCH_INFO`.

### `$&` (Matched Substring)

The matched string.

English - `$MATCH`.

### `` $` `` (Pre-Match Substring)
The string to the left of the match.

English - `$PREMATCH`.

### `$'` (Post-Match Substring)

The string to the right of the match.

English - `$POSTMATCH`.

### `$+` (Last Matched Group)

The last group matched.

English - `$LAST_PAREN_MATCH`.

### `$1`, `$2`, \Etc. (Matched Group)

For <tt>$_n_</tt> the <i>n</i>th group of the match.

No \English.

## Separators

### `$/` (Input Record Separator)

An input record separator, initially newline.

English - `$INPUT_RECORD_SEPARATOR`, `$RS`.

Aliased as `$-0`.

### `$\` (Output Record Separator)

An output record separator, initially `nil`.

English - `$OUTPUT_RECORD_SEPARATOR`, `$ORS`.

## Streams

### `$stdin` (Standard Input)

The current standard input stream; initially:

```ruby
$stdin # => #<IO:<STDIN>>
```

### `$stdout` (Standard Output)

The current standard output stream; initially:

```ruby
$stdout # => #<IO:<STDOUT>>
```

### `$stderr` (Standard Error)

The current standard error stream; initially:

```ruby
$stderr # => #<IO:<STDERR>>
```

### `$<` (\ARGF or $stdin)

Points to stream ARGF if not empty, else to stream $stdin; read-only.

English - `$DEFAULT_INPUT`.

### `$>` (Default Standard Output)

An output stream, initially `$stdout`.

English - `$DEFAULT_OUTPUT`

### `$.` (Input Position)

The input position (line number) in the most recently read stream.

English - `$INPUT_LINE_NUMBER`, `$NR`

### `$_` (Last Read Line)

The line (string) from the most recently read stream.

English - `$LAST_READ_LINE`.

## Processes

### `$0`

Initially, contains the name of the script being executed;
may be reassigned.

### `$*` (\ARGV)

Points to ARGV.

English - `$ARGV`.

### `$$` (Process ID)

The process ID of the current process. Same as Process.pid.

English - `$PROCESS_ID`, `$PID`.

### `$?` (Child Status)

Initially `nil`, otherwise the Process::Status object
created for the most-recently exited child process;
thread-local.

English - `$CHILD_STATUS`.

### `$LOAD_PATH` (Load Path)

Contains the array of paths to be searched
by Kernel#load and Kernel#require.

Singleton method `$LOAD_PATH.resolve_feature_path(feature)`
returns:

- <tt>[:rb, _path_]</tt>, where `path` is the path to the Ruby file to be
  loaded for the given `feature`.
- <tt>[:so, _path_]</tt>, where `path` is the path to the shared object file
  to be loaded for the given `feature`.
- `nil` if there is no such `feature` and `path`.

Examples:

```ruby
$LOAD_PATH.resolve_feature_path('timeout')
# => [:rb, "/snap/ruby/317/lib/ruby/3.2.0/timeout.rb"]
$LOAD_PATH.resolve_feature_path('date_core')
# => [:so, "/snap/ruby/317/lib/ruby/3.2.0/x86_64-linux/date_core.so"]
$LOAD_PATH.resolve_feature_path('foo')
# => nil
```

Aliased as `$:` and `$-I`.

### `$LOADED_FEATURES`

Contains an array of the paths to the loaded files:

```ruby
$LOADED_FEATURES.take(10)
# =>
["enumerator.so",
 "thread.rb",
 "fiber.so",
 "rational.so",
 "complex.so",
 "ruby2_keywords.rb",
 "/snap/ruby/317/lib/ruby/3.2.0/x86_64-linux/enc/encdb.so",
 "/snap/ruby/317/lib/ruby/3.2.0/x86_64-linux/enc/trans/transdb.so",
 "/snap/ruby/317/lib/ruby/3.2.0/x86_64-linux/rbconfig.rb",
 "/snap/ruby/317/lib/ruby/3.2.0/rubygems/compatibility.rb"]
```

Aliased as `$"`.

## Debugging

### `$FILENAME`

The value returned by method ARGF.filename.

### `$DEBUG`

Initially `true` if command-line option `-d` or `--debug` is given,
otherwise initially `false`;
may be set to either value in the running program.

When `true`, prints each raised exception to `$stderr`.

Aliased as `$-d`.

### `$VERBOSE`

Initially `true` if command-line option `-v` or `-w` is given,
otherwise initially `false`;
may be set to either value, or to `nil`, in the running program.

When `true`, enables Ruby warnings.

When `nil`, disables warnings, including those from Kernel#warn.

Aliased as `$-v` and `$-w`.

## Other Variables

### `$-a`

Whether command-line option `-a` was given; read-only.

### `$-i`

Contains the extension given with command-line option `-i`,
or `nil` if none.

An alias of ARGF.inplace_mode.

### `$-l`

Whether command-line option `-l` was set; read-only.

### `$-p`

Whether command-line option `-p` was given; read-only.

## Deprecated

### `$=`

### `$,`

### `$;`

# Pre-Defined Global Constants

## Summary

### Streams

| Constant | Contains                |
|----------|-------------------------|
| `STDIN`  | Standard input stream.  |
| `STDOUT` | Standard output stream. |
| `STDERR` | Standard error stream.  |

### Environment

| Constant              | Contains                                                                      |
|-----------------------|-------------------------------------------------------------------------------|
| `ENV`                 | Hash of current environment variable names and values.                        |
| `ARGF`                | String concatenation of files given on the command line, or `$stdin` if none. |
| `ARGV`                | Array of the given command-line arguments.                                    |
| `TOPLEVEL_BINDING`    | Binding of the top level scope.                                               |
| `RUBY_VERSION`        | String Ruby version.                                                          |
| `RUBY_RELEASE_DATE`   | String Ruby release date.                                                     |
| `RUBY_PLATFORM`       | String Ruby platform.                                                         |
| `RUBY_PATCH_LEVEL`    | String Ruby patch level.                                                      |
| `RUBY_REVISION`       | String Ruby revision.                                                         |
| `RUBY_COPYRIGHT`      | String Ruby copyright.                                                        |
| `RUBY_ENGINE`         | String Ruby engine.                                                           |
| `RUBY_ENGINE_VERSION` | String Ruby engine version.                                                   |
| `RUBY_DESCRIPTION`    | String Ruby description.                                                      |

### Embedded Data

| Constant | Contains                                                           |
|----------|--------------------------------------------------------------------|
| `DATA`   | File containing embedded data (lines following `__END__`, if any). |

## Streams

### `STDIN`

The standard input stream (the default value for `$stdin`):

```ruby
STDIN # => #<IO:<STDIN>>
```

### `STDOUT`

The standard output stream (the default value for `$stdout`):

```ruby
STDOUT # => #<IO:<STDOUT>>
```

### `STDERR`

The standard error stream (the default value for `$stderr`):

```ruby
STDERR # => #<IO:<STDERR>>
```

## Environment

### `ENV`

A hash of the contains current environment variables names and values:

```ruby
ENV.take(5)
# =>
[["COLORTERM", "truecolor"],
 ["DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus"],
 ["DESKTOP_SESSION", "ubuntu"],
 ["DISPLAY", ":0"],
 ["GDMSESSION", "ubuntu"]]
```

### `ARGF`

The virtual concatenation of the files given on the command line, or from
`$stdin` if no files were given, `"-"` is given, or after
all files have been read.

### `ARGV`

An array of the given command-line arguments.

### `TOPLEVEL_BINDING`

The Binding of the top level scope:

```ruby
TOPLEVEL_BINDING # => #<Binding:0x00007f58da0da7c0>
```

### `RUBY_VERSION`

The Ruby version:

```ruby
RUBY_VERSION # => "3.2.2"
```

### `RUBY_RELEASE_DATE`

The release date string:

```ruby
RUBY_RELEASE_DATE # => "2023-03-30"
```

### `RUBY_PLATFORM`

The platform identifier:

```ruby
RUBY_PLATFORM # => "x86_64-linux"
```

### `RUBY_PATCHLEVEL`

The integer patch level for this Ruby:

```ruby
RUBY_PATCHLEVEL # => 53
```

For a development build the patch level will be -1.

### `RUBY_REVISION`

The git commit hash for this Ruby:

```ruby
RUBY_REVISION # => "e51014f9c05aa65cbf203442d37fef7c12390015"
```

### `RUBY_COPYRIGHT`

The copyright string:

```ruby
RUBY_COPYRIGHT
# => "ruby - Copyright (C) 1993-2023 Yukihiro Matsumoto"
```

### `RUBY_ENGINE`

The name of the Ruby implementation:

```ruby
RUBY_ENGINE # => "ruby"
```

### `RUBY_ENGINE_VERSION`

The version of the Ruby implementation:

```ruby
RUBY_ENGINE_VERSION # => "3.2.2"
```

### `RUBY_DESCRIPTION`

The description of the Ruby implementation:

```ruby
RUBY_DESCRIPTION
# => "ruby 3.2.2 (2023-03-30 revision e51014f9c0) [x86_64-linux]"
```

## Embedded \Data

### `DATA`

Defined if and only if the program has this line:

```ruby
__END__
```

When defined, `DATA` is a File object
containing the lines following the `__END__`,
positioned at the first of those lines:

```ruby
p DATA
DATA.each_line { |line| p line }
__END__
Foo
Bar
Baz
```

Output:

```
#<File:t.rb>
"Foo\n"
"Bar\n"
"Baz\n"
```
