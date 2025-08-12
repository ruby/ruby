# Pre-Defined Global Variables

Some of the pre-defined global variables have synonyms
that are available via module English.
For each of those, the \English synonym is given.

To use the module:

```
require 'English'
```

## Summary

### Exceptions

| Variable    | English                  | Contains                                           |
|-------------|--------------------------|----------------------------------------------------|
| <tt>$!</tt> | <tt>$ERROR_INFO</tt>     | Exception object; set by Kernel#raise.             |
| <tt>$@</tt> | <tt>$ERROR_POSITION</tt> | Array of backtrace positions; set by Kernel#raise. |

### Pattern Matching

| Variable    | English                    | Contains                                         |
|-------------|----------------------------|--------------------------------------------------|
| <tt>$~</tt> | <tt>$LAST_MATCH_INFO</tt>  | MatchData object; set by matcher method.         |
| <tt>$&</tt> | <tt>$MATCH</tt>            | Matched substring; set by matcher method.        |
| <tt>$`</tt> | <tt>$PRE_MATCH</tt>        | Substring left of match; set by matcher method.  |
| <tt>$'</tt> | <tt>$POST_MATCH</tt>       | Substring right of match; set by matcher method. |
| <tt>$+</tt> | <tt>$LAST_PAREN_MATCH</tt> | Last group matched; set by matcher method.       |
| <tt>$1</tt> |                            | First group matched; set by matcher method.      |
| <tt>$2</tt> |                            | Second group matched; set by matcher method.     |
| <tt>$</tt>n |                            | nth group matched; set by matcher method.        |

### Separators

| Variable             | English                           | Contains                                         |
|----------------------|-----------------------------------|--------------------------------------------------|
| <tt>$/</tt>          | <tt>$INPUT_RECORD_SEPARATOR</tt>  | Input record separator; initially newline.       |
| <tt>$\\\\\\\\</tt>   | <tt>$OUTPUT_RECORD_SEPARATOR</tt> | Output record separator; initially <tt>nil</tt>. |

### Streams

| Variable         | English                                   | Contains                                                  |
|------------------|-------------------------------------------|-----------------------------------------------------------|
| <tt>$stdin</tt>  |                                           | Standard input stream; initially <tt>STDIN</tt>.          |
| <tt>$stdout</tt> |                                           | Standard input stream; initially <tt>STDIOUT</tt>.        |
| <tt>$stderr</tt> |                                           | Standard input stream; initially <tt>STDERR</tt>.         |
| <tt>$<</tt>      | <tt>$DEFAULT_INPUT</tt>                   | Default standard input; <tt>ARGF</tt> or <tt>$stdin</tt>. |
| <tt>$></tt>      | <tt>$DEFAULT_OUTPUT</tt>                  | Default standard output; initially <tt>$stdout</tt>.      |
| <tt>$.</tt>      | <tt>$INPUT_LINE_NUMBER</tt>, <tt>$NR</tt> | Input position of most recently read stream.              |
| <tt>$_</tt>      | <tt>$LAST_READ_LINE</tt>                  | String from most recently read stream.                    |

### Processes

| Variable                                       | English                             | Contains                                               |
|------------------------------------------------|-------------------------------------|--------------------------------------------------------|
| <tt>$0</tt>                                    |                                     | Initially, the name of the executing program.          |
| <tt>$*</tt>                                    | <tt>$ARGV</tt>                      | Points to the <tt>ARGV</tt> array.                                         |
| <tt>$$</tt>                                    | <tt>$PROCESS_ID</tt>, <tt>$PID</tt> | Process ID of the current process.                     |
| <tt>$?</tt>                                    | <tt>$CHILD_STATUS</tt>              | Process::Status of most recently exited child process. |
| <tt>$LOAD_PATH</tt>, <tt>$:</tt>, <tt>$-I</tt> |                                     | Array of paths to be searched.                         |
| <tt>$LOADED_FEATURES</tt>, <tt>$"</tt>         |                                     | Array of paths to loaded files.                        |

### Debugging

| Variable           | English | Contains                                                             |
|--------------------|---------|----------------------------------------------------------------------|
| <tt>$FILENAME</tt> |         | The value returned by method ARGF.filename.                          |
| <tt>$DEBUG</tt>    |         | Initially, whether option <tt>-d</tt> or <tt>--debug</tt> was given. |
| <tt>$VERBOSE</tt>  |         | Initially, whether option <tt>-V</tt> or <tt>-W</tt> was given.      |

### Other Variables

| Variable     | English | Contains                                              |
|--------------|---------|-------------------------------------------------------|
| <tt>$-a</tt> |         | Whether option <tt>-a</tt> was given.                 |
| <tt>$-i</tt> |         | Extension given with command-line option <tt>-i</tt>. |
| <tt>$-l</tt> |         | Whether option <tt>-l</tt> was given.                 |
| <tt>$-p</tt> |         | Whether option <tt>-p</tt> was given.                 |

## Exceptions

### `$!` (\Exception)

Contains the Exception object set by Kernel#raise:

```
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

```
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

For `$_n_` the _nth_ group of the match.

No \English.

## Separators

### `$/` (Input Record Separator)

An input record separator, initially newline.

English - `$INPUT_RECORD_SEPARATOR`, `$RS`.

Aliased as `$-0`.

### `$\\` (Output Record Separator)

An output record separator, initially +nil+.

English - `$OUTPUT_RECORD_SEPARATOR`, `$ORS`.

## Streams

### `$stdin` (Standard Input)

The current standard input stream; initially:

```
$stdin # => #<IO:<STDIN>>
```

### `$stdout` (Standard Output)

The current standard output stream; initially:

```
$stdout # => #<IO:<STDOUT>>
```

### `$stderr` (Standard Error)

The current standard error stream; initially:

```
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

Initially +nil+, otherwise the Process::Status object
created for the most-recently exited child process;
thread-local.

English - `$CHILD_STATUS`.

### `$LOAD_PATH` (Load Path)

Contains the array of paths to be searched
by Kernel#load and Kernel#require.

Singleton method `$LOAD_PATH.resolve_feature_path(feature)`
returns:

- `[:rb, _path_]`, where +path+ is the path to the Ruby file
  to be loaded for the given +feature+.
- `[:so, _path_]`, where +path+ is the path to the shared object file
  to be loaded for the given +feature+.
- +nil+ if there is no such +feature+ and +path+.

Examples:

```
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

```
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

Initially +true+ if command-line option `-d` or `--debug` is given,
otherwise initially +false+;
may be set to either value in the running program.

When +true+, prints each raised exception to `$stderr`.

Aliased as `$-d`.

### `$VERBOSE`

Initially +true+ if command-line option `-v` or `-w` is given,
otherwise initially +false+;
may be set to either value, or to +nil+, in the running program.

When +true+, enables Ruby warnings.

When +nil+, disables warnings, including those from Kernel#warn.

Aliased as `$-v` and `$-w`.

## Other Variables

### `$-a`

Whether command-line option `-a` was given; read-only.

### `$-i`

Contains the extension given with command-line option `-i`,
or +nil+ if none.

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

| Constant        | Contains                |
|-----------------|-------------------------|
| <tt>STDIN</tt>  | Standard input stream.  |
| <tt>STDOUT</tt> | Standard output stream. |
| <tt>STDERR</tt> | Standard error stream.  |

### Environment

| Constant                     | Contains                                                                             |
|------------------------------|--------------------------------------------------------------------------------------|
| <tt>ENV</tt>                 | Hash of current environment variable names and values.                               |
| <tt>ARGF</tt>                | String concatenation of files given on the command line, or <tt>$stdin</tt> if none. |
| <tt>ARGV</tt>                | Array of the given command-line arguments.                                           |
| <tt>TOPLEVEL_BINDING</tt>    | Binding of the top level scope.                                                      |
| <tt>RUBY_VERSION</tt>        | String Ruby version.                                                                 |
| <tt>RUBY_RELEASE_DATE</tt>   | String Ruby release date.                                                            |
| <tt>RUBY_PLATFORM</tt>       | String Ruby platform.                                                                |
| <tt>RUBY_PATCH_LEVEL</tt>    | String Ruby patch level.                                                             |
| <tt>RUBY_REVISION</tt>       | String Ruby revision.                                                                |
| <tt>RUBY_COPYRIGHT</tt>      | String Ruby copyright.                                                               |
| <tt>RUBY_ENGINE</tt>         | String Ruby engine.                                                                  |
| <tt>RUBY_ENGINE_VERSION</tt> | String Ruby engine version.                                                          |
| <tt>RUBY_DESCRIPTION</tt>    | String Ruby description.                                                             |

### Embedded Data

| Constant      | Contains                                                                  |
|---------------|---------------------------------------------------------------------------|
| <tt>DATA</tt> | File containing embedded data (lines following <tt>__END__</tt>, if any). |

## Streams

### `STDIN`

The standard input stream (the default value for `$stdin`):

```
STDIN # => #<IO:<STDIN>>
```

### `STDOUT`

The standard output stream (the default value for `$stdout`):

```
STDOUT # => #<IO:<STDOUT>>
```

### `STDERR`

The standard error stream (the default value for `$stderr`):

```
STDERR # => #<IO:<STDERR>>
```

## Environment

### ENV

A hash of the contains current environment variables names and values:

```
ENV.take(5)
# =>
[["COLORTERM", "truecolor"],
 ["DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus"],
 ["DESKTOP_SESSION", "ubuntu"],
 ["DISPLAY", ":0"],
 ["GDMSESSION", "ubuntu"]]
```

### ARGF

The virtual concatenation of the files given on the command line, or from
`$stdin` if no files were given, `"-"` is given, or after
all files have been read.

### `ARGV`

An array of the given command-line arguments.

### `TOPLEVEL_BINDING`

The Binding of the top level scope:

```
TOPLEVEL_BINDING # => #<Binding:0x00007f58da0da7c0>
```

### `RUBY_VERSION`

The Ruby version:

```
RUBY_VERSION # => "3.2.2"
```

### `RUBY_RELEASE_DATE`

The release date string:

```
RUBY_RELEASE_DATE # => "2023-03-30"
```

### `RUBY_PLATFORM`

The platform identifier:

```
RUBY_PLATFORM # => "x86_64-linux"
```

### `RUBY_PATCHLEVEL`

The integer patch level for this Ruby:

```
RUBY_PATCHLEVEL # => 53
```

For a development build the patch level will be -1.

### `RUBY_REVISION`

The git commit hash for this Ruby:

```
RUBY_REVISION # => "e51014f9c05aa65cbf203442d37fef7c12390015"
```

### `RUBY_COPYRIGHT`

The copyright string:

```
RUBY_COPYRIGHT
# => "ruby - Copyright (C) 1993-2023 Yukihiro Matsumoto"
```

### `RUBY_ENGINE`

The name of the Ruby implementation:

```
RUBY_ENGINE # => "ruby"
```

### `RUBY_ENGINE_VERSION`

The version of the Ruby implementation:

```
RUBY_ENGINE_VERSION # => "3.2.2"
```

### `RUBY_DESCRIPTION`

The description of the Ruby implementation:

```
RUBY_DESCRIPTION
# => "ruby 3.2.2 (2023-03-30 revision e51014f9c0) [x86_64-linux]"
```

## Embedded \Data

### `DATA`

Defined if and only if the program has this line:

```
__END__
```

When defined, `DATA` is a File object
containing the lines following the `__END__`,
positioned at the first of those lines:

```
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
