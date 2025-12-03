# Pre-Defined Global Variables

Some of the pre-defined global variables have synonyms
that are available via module English.
For each of those, the \English synonym is given.

To use the module:

```ruby
require 'English'
```

## In Brief

### Exceptions

|  Variable   |         \English         |  Initially   | Read-Only | Set By                                         |
|:-----------:|:------------------------:|:------------:|:---------:|------------------------------------------------|
| <tt>$!</tt> |   <tt>$ERROR_INFO</tt>   | <tt>nil</tt> |   Yes.    | Kernel#raise, to Exception object.             |
| <tt>$@</tt> | <tt>$ERROR_POSITION</tt> | <tt>nil</tt> |   Yes.    | Kernel#raise, to array of backtrace positions. |

### Pattern Matching

|         Variable          |          \English          |  Initially   | Read-Only | Set By                                                       |
|:-------------------------:|:--------------------------:|:------------:|:---------:|--------------------------------------------------------------|
|        <tt>$~</tt>        | <tt>$LAST_MATCH_INFO</tt>  | <tt>nil</tt> |    No.    | Matcher method: to MatchData object or <tt>nil</tt>.         |
|        <tt>$&</tt>        |      <tt>$MATCH</tt>       | <tt>nil</tt> |    No.    | Matcher method: to matched substring or <tt>nil</tt>.        |
|        <tt>$`</tt>        |    <tt>$PRE_MATCH</tt>     | <tt>nil</tt> |    No.    | Matcher method: to substring left of match or <tt>nil</tt>.  |
|        <tt>$'</tt>        |    <tt>$POST_MATCH</tt>    | <tt>nil</tt> |    No.    | Matcher method: to substring right of match or <tt>nil</tt>. |
|        <tt>$+</tt>        | <tt>$LAST_PAREN_MATCH</tt> | <tt>nil</tt> |    No.    | Matcher method: to last group matched or <tt>nil</tt>.       |
|        <tt>$1</tt>        |                            | <tt>nil</tt> |    No.    | Matcher method: to first group matched or <tt>nil</tt>.      |
|        <tt>$2</tt>        |                            | <tt>nil</tt> |    No.    | Matcher method: to second group matched or <tt>nil</tt>.     |
|       <tt>$_n_</tt>       |                            | <tt>nil</tt> |    No.    | Matcher method: to <i>n</i>th group matched or <tt>nil</tt>. |

### Separators

|    Variable    |             \English              |  Initially   | Read-Only |
|:--------------:|:---------------------------------:|:------------:|:---------:|
|  <tt>$/</tt>   | <tt>$INPUT_RECORD_SEPARATOR</tt>  |   Newline.   |    No.    |
| <tt>$\\\\</tt> | <tt>$OUTPUT_RECORD_SEPARATOR</tt> | <tt>nil</tt> |    No.    |

### Streams

|    Variable      |                 \English                  |       Initially       | Read-Only | Set By                |
|:----------------:|:-----------------------------------------:|:---------------------:|:---------:|-----------------------|
| <tt>$stdin</tt>  |                                           |    <tt>STDIN</tt>     |    No.    |                       |
| <tt>$stdout</tt> |                                           |    <tt>STDOUT</tt>    |    No.    |                       |
| <tt>$stderr</tt> |                                           |    <tt>STDERR</tt>    |    No.    |                       |
|   <tt>$<</tt>    |          <tt>$DEFAULT_INPUT</tt>          |     <tt>ARGF</tt>     |   Yes.    |                       |
|   <tt>$></tt>    |         <tt>$DEFAULT_OUTPUT</tt>          |    <tt>STDOUT</tt>    |    No.    |                       |
|   <tt>$></tt>    |         <tt>$DEFAULT_OUTPUT</tt>          |   <tt>STDOUT </tt>    |    No.    |                       |
|   <tt>$.</tt>    | <tt>$INPUT_LINE_NUMBER</tt>, <tt>$NR</tt> | Non-negative integer. |    No.    | Certain read methods. |
|   <tt>$_</tt>    |         <tt>$LAST_READ_LINE</tt>          |     <tt>nil</tt>      |    No.    | Certain read methods. |

### Processes

|                    Variable                    |                     \English        |       Initially       | Read-Only |
|:----------------------------------------------:|:-----------------------------------:|:---------------------:|:---------:|
|                <tt>$0</tt>                     |                                     |     Program name.     |    No.    |
|                  <tt>$*</tt>                   |           <tt>$ARGV</tt>            |     <tt>ARGV</tt>     |   Yes.    |
|                  <tt>$$</tt>                   | <tt>$PROCESS_ID</tt>, <tt>$PID</tt> |     Process PID.      |   Yes.    |
|                  <tt>$?</tt>                   |       <tt>$CHILD_STATUS</tt>        | Child process status. |   Yes.    |
| <tt>$LOAD_PATH</tt>, <tt>$:</tt>, <tt>$-I</tt> |                                     |    Array of paths.    |   Yes.    |
|     <tt>$LOADED_FEATURES</tt>, <tt>$"</tt>     |                                     |   Array of paths.     |   Yes.    |

### Debugging

|    Variable        | \English |                         Initially                         | Read-Only | Set By        |
|:------------------:|:--------:|:---------------------------------------------------------:|:---------:|---------------|
| <tt>$FILENAME</tt> |          |   The value returned by method <tt>ARGF#filename</tt>.    |   Yes.    | <tt>ARGF</tt> |
|  <tt>$DEBUG</tt>   |          | Whether option <tt>-d</tt> or <tt>--debug</tt> was given. |    No.    |               |
| <tt>$VERBOSE</tt>  |          |   Whether option <tt>-V</tt> or <tt>-W</tt> was given.    |    No.    |               |

### Other Variables

| Variable      | \English |                     Initially                         | Read-Only |
|:-------------:|:--------:|:-----------------------------------------------------:|:---------:|
| <tt>$-a</tt>  |          |         Whether option <tt>-a</tt> was given.         |   Yes.    |
| <tt>$-i</tt>  |          | Extension given with command-line option <tt>-i</tt>. |    No.    |
| <tt>$-l</tt>  |          |         Whether option <tt>-l</tt> was given.         |   Yes.    |
| <tt>$-p</tt>  |          |         Whether option <tt>-p</tt> was given.         |   Yes.    |

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

### `$\\\` (Output Record Separator)

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
| <tt>STDIN</tt>  | Standard input stream.  |
| <tt>STDOUT</tt> | Standard output stream. |
| <tt>STDERR</tt> | Standard error stream.  |

### Environment

| Constant              | Contains                                                                      |
|-----------------------|-------------------------------------------------------------------------------|
| <tt>ENV</tt>                 | Hash of current environment variable names and values.                        |
| <tt>ARGF</tt>                | String concatenation of files given on the command line, or <tt>$stdin</tt> if none. |
| <tt>ARGV</tt>                | Array of the given command-line arguments.                                    |
| <tt>TOPLEVEL_BINDING</tt>    | Binding of the top level scope.                                               |
| <tt>RUBY_VERSION</tt>        | String Ruby version.                                                          |
| <tt>RUBY_RELEASE_DATE</tt>   | String Ruby release date.                                                     |
| <tt>RUBY_PLATFORM</tt>       | String Ruby platform.                                                         |
| <tt>RUBY_PATCH_LEVEL</tt>    | String Ruby patch level.                                                      |
| <tt>RUBY_REVISION</tt>       | String Ruby revision.                                                         |
| <tt>RUBY_COPYRIGHT</tt>      | String Ruby copyright.                                                        |
| <tt>RUBY_ENGINE</tt>         | String Ruby engine.                                                           |
| <tt>RUBY_ENGINE_VERSION</tt> | String Ruby engine version.                                                   |
| <tt>RUBY_DESCRIPTION</tt>    | String Ruby description.                                                      |

### Embedded \Data

| Constant      | Contains                                                                    |
|---------------|-----------------------------------------------------------------------------|
| <tt>DATA</tt> | File containing embedded data (lines following <tt>'__END__'</tt>, if any). |

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
