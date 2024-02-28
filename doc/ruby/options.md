# Ruby Command-Line Options

## About the Examples

Some examples here use command-line option `-e`,
which passes the Ruby code to be executed on the command line itself:

```sh
$ ruby -e 'puts "Hello, World."'
```

Some examples here assume that file `desiderata.txt` exists:

```
$ cat desiderata.txt
Go placidly amid the noise and the haste,
and remember what peace there may be in silence.
As far as possible, without surrender,
be on good terms with all persons.
```

## Options

### Option `-0`: \Set `$/` (Input Record Separator)

Option `-0` defines the input record separator `$/`
for the invoked Ruby program.

The optional argument to the option must be octal digits,
each in the range `0..7`;
these digits are prefixed with digit `0` to form an octal value.

If no argument is given, the input record separator is `0x00`.

If an argument is given, it must immediately follow the option
(no whitespace or equal-sign character `'-'`);
argument values:

- `0`: the input record separator is `''`;
  see {Special Line Separator Values}[rdoc-ref:IO@Special+Line+Separator+Values].
- In range `(1..0377)`:
  the input record separator `$/` is set to the character value of the argument.
- Any other value: the input record separator is `nil`.

Examples:

```sh
$ ruby -0 -e 'p $/'
"\x00"
ruby -00 -e 'p $/'
""
$ ruby -012 -e 'p $/'
"\n"
$ ruby -015 -e 'p $/'
"\r"
$ ruby -0377 -e 'p $/'
"\xFF"
$ ruby -0400 -e 'p $/'
nil
```

See also:

- {Option -a}[rdoc-ref:options.md@Option+-a-3A+Split+Input+Lines+into+Fields]: : Split input lines into fields.
- {Option -F}[rdoc-ref:options.md@Option+-F-3A+Set+Input+Field+Separator]: \Set input field separator.
- {Option -n}[rdoc-ref:options.md@Option+-n-3A+Run+Program+in+gets+Loop]: Run program in `gets` loop.
- {Option -p}[rdoc-ref:options.md@Option+-p-3A+-n-2C+with+Printing]: `-n`, with printing.

### Option `-a`: Split Input Lines into Fields

Option `-a`, when given with either of options `-n` or `-p`,
splits the string at `$_` into an array of strings at `$F`:

```sh
$ ruby -an -e 'p $F' desiderata.txt
["Go", "placidly", "amid", "the", "noise", "and", "the", "haste,"]
["and", "remember", "what", "peace", "there", "may", "be", "in", "silence."]
["As", "far", "as", "possible,", "without", "surrender,"]
["be", "on", "good", "terms", "with", "all", "persons."]
```

For the splitting,
the default record separator is `$/`,
and the default field separator  is `$;`.

See also:

- {Option -0}[rdoc-ref:options.md@Option+-0-3A+Set+-24-2F+-28Input+Record+Separator-29]: \Set `$/` (input record separator).
- {Option -F}[rdoc-ref:options.md@Option+-F-3A+Set+Input+Field+Separator]: \Set input field separator.
- {Option -n}[rdoc-ref:options.md@Option+-n-3A+Run+Program+in+gets+Loop]: Run program in `gets` loop.
- {Option -p}[rdoc-ref:options.md@Option+-p-3A+-n-2C+with+Printing]: `-n`, with printing.

### Option `-c`: Check Syntax

Option `-c` specifies that the specified Ruby program
should be checked for syntax, but not actually executed:

```
$ ruby -e 'puts "Foo"'
Foo
$ ruby -c -e 'puts "Foo"'
Syntax OK
```

### Option `-C`: \Set Working Directory

The argument to option `-C` specifies a working directory
for the invoked Ruby program;
does not change the working directory for the current process:

```sh
$ basename `pwd`
ruby
$ ruby -C lib -e 'puts File.basename(Dir.pwd)'
lib
$ basename `pwd`
ruby
```

Whitespace between the option and its argument may be omitted.

### Option `-d`: \Set `$DEBUG` to `true`

Some code in (or called by) the Ruby program may include statements or blocks
conditioned by the global variable `$DEBUG` (e.g., `if $DEBUG`);
these commonly write to `$stdout` or `$stderr`.

The default value for `$DEBUG` is `false`;
option `-d` sets it to `true`:

```sh
$ ruby -e 'p $DEBUG'
false
$ ruby -d -e 'p $DEBUG'
true
```

Option `--debug` is an alias for option `-d`.

### Option `-e`: Execute Given Ruby Code

Option `-e` requires an argument, which is Ruby code to be executed;
the option may be given more than once:

```
$ ruby -e 'puts "Foo"' -e 'puts "Bar"'
Foo
Bar
```

Whitespace between the option and its argument may be omitted.

The command may include other options,
but should not include arguments (which, if given, are ignored).

### Option `-E`: \Set Default Encodings

Option `-E` requires an argument, which specifies either the default external encoding,
or both the default external and internal encodings for the invoked Ruby program:

```
# No option -E.
$ ruby -e 'p [Encoding::default_external, Encoding::default_internal]'
[#<Encoding:UTF-8>, nil]
# Option -E with default external encoding.
$ ruby -E cesu-8 -e 'p [Encoding::default_external, Encoding::default_internal]'
[#<Encoding:CESU-8>, nil]
# Option -E with default external and internal encodings.
$ ruby -E cesu-8:cesu-8 -e 'p [Encoding::default_external, Encoding::default_internal]'
[#<Encoding:CESU-8>, #<Encoding:CESU-8>]
```

Whitespace between the option and its argument may be omitted.

See also:

- {Option --external-encoding}[rdoc-ref:options.md@Option+--external-encoding-3A+Set+Default+External+Encoding]:
  \Set default external encoding.
- {Option --internal-encoding}[rdoc-ref:options.md@Option+--internal-encoding-3A+Set+Default+Internal+Encoding]:
  \Set default internal encoding.

Option `--encoding` is an alias for option `-E`.

### Option `-F`: \Set Input Field Separator

Option `-F`, when given with option `-a`,
specifies that its argument is to be the input field separator to be used for splitting:

```sh
$ ruby -an -Fs -e 'p $F' desiderata.txt
["Go placidly amid the noi", "e and the ha", "te,\n"]
["and remember what peace there may be in ", "ilence.\n"]
["A", " far a", " po", "", "ible, without ", "urrender,\n"]
["be on good term", " with all per", "on", ".\n"]
```

The argument may be a regular expression:

```
$ ruby -an -F'[.,]\s*' -e 'p $F' desiderata.txt
["Go placidly amid the noise and the haste"]
["and remember what peace there may be in silence"]
["As far as possible", "without surrender"]
["be on good terms with all persons"]
```

### Option `-h`: Print Short Help Message

Option `-h` prints a short help message
that includes single-hyphen options (e.g. `-I`),
and largely omits double-hyphen options (e.g., `--version`).

Arguments and additional options are ignored.

For a longer help message, use option `--help`.

### Option `-i`: \Set ARGF In-Place Mode

Option `-i` sets the ARGF in-place mode for the invoked Ruby program;
see ARGF#inplace_mode=:

```
$ ruby -e 'p ARGF.inplace_mode'
nil
$ ruby -i -e 'p ARGF.inplace_mode'
""
$ ruby -i.bak -e 'p ARGF.inplace_mode'
".bak"
```

### Option `-I`: Add to `$LOAD_PATH`

The argument to option `-I` specifies a directory
to be added to the array in global variable `$LOAD_PATH`;
the option may be given more than once:

```sh
$ pushd /tmp
$ ruby -e 'p $LOAD_PATH.size'
8
$ ruby -I my_lib -I some_lib -e 'p $LOAD_PATH.size'
10
$ ruby -I my_lib -I some_lib -e 'p $LOAD_PATH.take(2)'
["/tmp/my_lib", "/tmp/some_lib"]
$ popd
```

Whitespace between the option and its argument may be omitted.

### Option `-l`: \Set Output Record Separator; Chop Lines

Option `-l`, when given with option `-n` or `-p`,
modifies line-ending processing by:

- Setting global variable output record separator `$\`
  to input record separator `$/`;
  this affects line-oriented output (such a that from Kernel#puts).
- Calling String#chop! on each line read.

Without option `-l` (unchopped):

```sh
$ ruby -n -e 'p $_' desiderata.txt
"Go placidly amid the noise and the haste,\n"
"and remember what peace there may be in silence.\n"
"As far as possible, without surrender,\n"
"be on good terms with all persons.\n"
```

With option `-l' (chopped):

```sh
$ ruby -ln -e 'p $_' desiderata.txt
"Go placidly amid the noise and the haste,"
"and remember what peace there may be in silence."
"As far as possible, without surrender,"
"be on good terms with all persons."
```

### Option `-n`: Run Program in `gets` Loop

Option `-n` runs your program in a Kernel#gets loop:

```
while gets
  # Your Ruby code.
end
```

Note that `gets` reads the next line and sets global variable `$_`
to the last read line:

```sh
$ ruby -n -e 'puts $_' desiderata.txt
Go placidly amid the noise and the haste,
and remember what peace there may be in silence.
As far as possible, without surrender,
be on good terms with all persons.
```

### Option `-p`: `-n`, with Printing

Option `-p` is like option `-n`, but also prints each line:

```sh
$ ruby -p -e 'puts $_.size' desiderata.txt
42
Go placidly amid the noise and the haste,
49
and remember what peace there may be in silence.
39
As far as possible, without surrender,
35
be on good terms with all persons.
```

### Option `-r`: Require Library

The argument to option `-r` specifies a library to be required
before executing the Ruby program;
the option may be given more than once:

```sh
$ ruby -e 'p defined?(JSON); p defined?(CSV)'
nil
nil
$ ruby -r CSV -r JSON -e 'p defined?(JSON); p defined?(CSV)'
"constant"
"constant"
```

Whitespace between the option and its argument may be omitted.

### Option `-s`: Define Global Variable

Option `-s` specifies that a "custom option" that follows
the script name is to define a global variable in the invoked Ruby program:

- The custom option must begin with single hyphen (`-foo`), not two hyphens (`--foo`).
- The name of the global variable is based on the option name: `$foo` for `-foo`.
- The value of the global variable is the string option argument if given,
  `true` otherwise.

More than one custom option may be given:

```
$ cat t.rb
p [$foo, $bar]
$ ruby t.rb
[nil, nil]
$ ruby -s t.rb -foo=baz
["baz", nil]
$ ruby -s t.rb -foo
[true, nil]
$ ruby -s t.rb -foo=baz -bar=bat
["baz", "bat"]
```

### Option `-S`: Search Directories in `ENV['PATH']

Option `-S` specifies that the Ruby interpreter
is to search (if necessary) the directories whose paths are in the program's
`PATH` environment variable;
the program is executed in the shell's current working directory
(not the directory where the program is found).

This example uses adds path `'tmp/'` to the `PATH` environment variable:

```sh
$ export PATH=/tmp:$PATH
$ echo "puts File.basename(Dir.pwd)" > /tmp/t.rb
$ ruby -S t.rb
ruby
```

### Option `-v`: Print Version; \Set `$VERBOSE`

Options `-v` prints the Ruby version and sets global variable `$VERBOSE`:

```
$ ruby -e 'p $VERBOSE'
false
$ ruby -v -e 'p $VERBOSE'
ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [x64-mingw-ucrt]
true
```

### Option `-w`: Synonym for `-W1`

Option `-w` (lowercase letter) is equivalent to option `-W1` (uppercase letter).

### Option `-W`: \Set Warning Policy

Any Ruby code can create a <i>warning message</i> by calling method Kernel#warn;
methods in the Ruby core and standard libraries can also create warning messages.
Such a message may be printed on `$stderr`
(or not, depending on certain settings).

Option `-W` helps determine whether a particular warning message
will be written,
by setting the initial value of global variable `$-W`:

- `-W0`: Sets `$-W` to `0` (silent; no warnings).
- `-W1`: Sets `$-W` to `1` (moderate verbosity).
- `-W2`: Sets `$-W` to `2` (high verbosity).
- `-W`: Same as `-W2` (high verbosity).
- Option not given: Same as `-W1` (moderate verbosity).

The value of `$-W`, in turn, determines which warning messages (if any)
are to be printed to `$stdout` (see Kernel#warn):

```sh
$ ruby -W1 -e 'p $foo'
nil
$ ruby -W2 -e 'p $foo'
-e:1: warning: global variable '$foo' not initialized
nil
```

Ruby code may also define warnings for certain categories;
these are the default settings for the defined categories:

```
Warning[:experimental] # => true
Warning[:deprecated]   # => false
Warning[:performance]  # => false
```

They may also be set:
```
Warning[:experimental] = false
Warning[:deprecated]   = true
Warning[:performance]  = true
```

You can suppress a category by prefixing `no-` to the category name:

```
$ ruby -W:no-experimental -e 'p IO::Buffer.new'
#<IO::Buffer>
```

### Option `-x`: Execute Ruby Code Found in Text

Option `-x` executes a Ruby program whose code is embedded
in other, non-code, text:

The ruby code:

- Begins after the first line beginning with `'#!` and containing string `'ruby'`.
- Ends before any one of:

    - End-of-file.
    - A line consisting of `'__END__'`,
    - Character `Ctrl-D` or `Ctrl-Z`.

Example:

```sh
$ cat t.txt
Leading garbage.
#!ruby
puts File.basename(Dir.pwd)
__END__
Trailing garbage.

$ ruby -x t.txt
ruby
```

The optional argument specifies the directory where the text file
is to be found;
the Ruby code is executed in that directory:

```sh
$ cp t.txt /tmp/
$ ruby -x/tmp t.txt
tmp
$

```

The option and its argument may not be separated by whitespace.

### Option `--backtrace-limit`: \Set Backtrace Limit

Option `--backtrace-limit` sets a limit on the number of entries
to be displayed in a backtrace.

### Option `--copyright`: Print Ruby Copyright

Option `--copyright` prints a copyright message:

```sh
$ ruby --copyright
ruby - Copyright (C) 1993-2021 Yukihiro Matsumoto
```

### Option `--debug`: Alias for `-d`

Option `--debug` is an alias for
{option -d}[rdoc-ref:options.md@Option+-d-3A+Set+-24DEBUG+to+true].

### Option `--disable`: Disable Features

Option `--disable` specifies features to be disabled;
_list_ is a comma-separated list of the features to be disabled.

The supported features:

- `gems`: Rubygems (default: enabled).
- `did_you_mean`: `did_you_mean` (default: enabled).
- `rubyopt`: `RUBYOPT` environment variable (default: enabled).
- `frozen-string-literal`: Freeze all string literals (default: disabled).
- `jit`: JIT compiler (default: disabled).

### Option `--dump`: Dump Items

Option `--dump` specifies items to be dumped;
_list_ is a comma-separated list of the items.

The supported items:

- `insns`: Instruction sequences.
- `yydebug`: yydebug of yacc parser generator.
- `parsetree` {AST}[https://en.wikipedia.org/wiki/Abstract_syntax_tree].
- `parsetree_with_comment`: AST with comments.

### Option `--enable`: Enable Features

Option `--enable` specifies features to be enabled;
_list_ is a comma-separated list of the features to be enabled.

See {option --disable}[rdoc-ref:options.md@Option+--disable-3A+Disable+Features].

### Option `--encoding`: Alias for `-E`.

Option `--encoding` is an alias for
{option -E}[rdoc-ref:options.md@Option+-E-3A+Set+Default+Encodings].

### Option `--external-encoding`: \Set Default External Encoding

Option `--external-encoding`
sets the default external encoding for the invoked Ruby program;
for values of +encoding+,
see {Encoding: Names and Aliases}[rdoc-ref:encodings.rdoc@Names+and+Aliases].

```sh
$ ruby -e 'puts Encoding::default_external'
UTF-8
$ ruby --external-encoding=cesu-8 -e 'puts Encoding::default_external'
CESU-8
```

### Option `--help`: Print Help Message

Option `--help` prints a long help message.

Arguments and additional options are ignored.

For a shorter help message, use option `-h`.

### Option `--internal-encoding`: \Set Default Internal Encoding

Option `--internal-encoding`
sets the default internal encoding for the invoked Ruby program;
for values of +encoding+,
see {Encoding: Names and Aliases}[rdoc-ref:encodings.rdoc@Names+and+Aliases].

```sh
$ ruby -e 'puts Encoding::default_internal.nil?'
true
$ ruby --internal-encoding=cesu-8 -e 'puts Encoding::default_internal'
CESU-8
```

### Option `--verbose`: \Set `$VERBOSE`

Option `--verbose` sets global variable `$VERBOSE` to `true`
and disables input from `$stdin`.

### Option `--version`: Print Ruby Version

Option `--version` prints the version of the Ruby interpreter, then exits.

## Experimental Options

These options are experimental in the current Ruby release,
and may be modified or withdrawn in later releases.

### Option `--jit`

Option `-jit` enables JIT compilation with the default option.

#### Option `--jit-debug`

Option `--jit-debug` enables JIT debugging (very slow);
adds compiler flags if given.

#### Option `--jit-max-cache=num`

Option `--jit-max-cache=num` sets the maximum number of methods
to be JIT-ed in a cache; default: 100).

#### Option `--jit-min-calls=num`

Option `jit-min-calls=num` sets the minimum number of calls to trigger JIT
(for testing); default: 10000).

#### Option `--jit-save-temps`

Option `--jit-save-temps` saves JIT temporary files in $TMP or /tmp (for testing).

#### Option `--jit-verbose`

Option `--jit-verbose` prints JIT logs of level `num` or less
to `$stderr`; default: 0.

#### Option `--jit-wait`

Option `--jit-wait` waits until JIT compilation finishes every time (for testing).

####  Option `--jit-warnings`

Option `--jit-warnings` enables printing of JIT warnings.

