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

### `-0`: \Set `$/` (Input Record Separator)

Option `-0` defines the input record separator `$/`
for the invoked Ruby program.

The optional argument to the option must be octal digits,
each in the range `0..7`;
these digits are prefixed with digit `0` to form an octal value.

If no argument is given, the input record separator is `0x00`.

If an argument is given, it must immediately follow the option
(no intervening whitespace or equal-sign character `'='`);
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

- {Option -a}[options_md.html#label-a-3A+Split+Input+Lines+into+Fields]:
  Split input lines into fields.
- {Option -F}[options_md.html#label-F-3A+Set+Input+Field+Separator]:
  \Set input field separator.
- {Option -l}[options_md.html#label-l-3A+Set+Output+Record+Separator-3B+Chop+Lines]:
  \Set output record separator; chop lines.
- {Option -n}[options_md.html#label-n-3A+Run+Program+in+gets+Loop]:
  Run program in `gets` loop.
- {Option -p}[options_md.html#label-p-3A+-n-2C+with+Printing]:
  `-n`, with printing.

### `-a`: Split Input Lines into Fields

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

- {Option -0}[options_md.html#label-0-3A+Set+-24-2F+-28Input+Record+Separator-29]:
  \Set `$/` (input record separator).
- {Option -F}[options_md.html#label-F-3A+Set+Input+Field+Separator]:
  \Set input field separator.
- {Option -l}[options_md.html#label-l-3A+Set+Output+Record+Separator-3B+Chop+Lines]:
  \Set output record separator; chop lines.
- {Option -n}[options_md.html#label-n-3A+Run+Program+in+gets+Loop]:
  Run program in `gets` loop.
- {Option -p}[options_md.html#label-p-3A+-n-2C+with+Printing]:
  `-n`, with printing.

### `-c`: Check Syntax

Option `-c` specifies that the specified Ruby program
should be checked for syntax, but not actually executed:

```
$ ruby -e 'puts "Foo"'
Foo
$ ruby -c -e 'puts "Foo"'
Syntax OK
```

### `-C`: \Set Working Directory

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

### `-d`: \Set `$DEBUG` to `true`

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

### `-e`: Execute Given Ruby Code

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

### `-E`: \Set Default Encodings

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

- {Option --external-encoding}[options_md.html#label--external-encoding-3A+Set+Default+External+Encoding]:
  \Set default external encoding.
- {Option --internal-encoding}[options_md.html#label--internal-encoding-3A+Set+Default+Internal+Encoding]:
  \Set default internal encoding.

Option `--encoding` is an alias for option `-E`.

### `-F`: \Set Input Field Separator

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

The argument must immediately follow the option
(no intervening whitespace or equal-sign character `'='`).

See also:

- {Option -0}[options_md.html#label-0-3A+Set+-24-2F+-28Input+Record+Separator-29]:
  \Set `$/` (input record separator).
- {Option -a}[options_md.html#label-a-3A+Split+Input+Lines+into+Fields]:
  Split input lines into fields.
- {Option -l}[options_md.html#label-l-3A+Set+Output+Record+Separator-3B+Chop+Lines]:
  \Set output record separator; chop lines.
- {Option -n}[options_md.html#label-n-3A+Run+Program+in+gets+Loop]:
  Run program in `gets` loop.
- {Option -p}[options_md.html#label-p-3A+-n-2C+with+Printing]:
  `-n`, with printing.

### `-h`: Print Short Help Message

Option `-h` prints a short help message
that includes single-hyphen options (e.g. `-I`),
and largely omits double-hyphen options (e.g., `--version`).

Arguments and additional options are ignored.

For a longer help message, use option `--help`.

### `-i`: \Set \ARGF In-Place Mode

Option `-i` sets the \ARGF in-place mode for the invoked Ruby program;
see ARGF#inplace_mode=:

```
$ ruby -e 'p ARGF.inplace_mode'
nil
$ ruby -i -e 'p ARGF.inplace_mode'
""
$ ruby -i.bak -e 'p ARGF.inplace_mode'
".bak"
```

### `-I`: Add to `$LOAD_PATH`

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

### `-l`: \Set Output Record Separator; Chop Lines

Option `-l`, when given with option `-n` or `-p`,
modifies line-ending processing by:

- Setting global variable output record separator `$\`
  to the current value of input record separator `$/`;
  this affects line-oriented output (such a the output from Kernel#puts).
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

See also:

- {Option -0}[options_md.html#label-0-3A+Set+-24-2F+-28Input+Record+Separator-29]:
  \Set `$/` (input record separator).
- {Option -a}[options_md.html#label-a-3A+Split+Input+Lines+into+Fields]:
  Split input lines into fields.
- {Option -F}[options_md.html#label-F-3A+Set+Input+Field+Separator]:
  \Set input field separator.
- {Option -n}[options_md.html#label-n-3A+Run+Program+in+gets+Loop]:
  Run program in `gets` loop.
- {Option -p}[options_md.html#label-p-3A+-n-2C+with+Printing]:
  `-n`, with printing.

### `-n`: Run Program in `gets` Loop

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

See also:

- {Option -0}[options_md.html#label-0-3A+Set+-24-2F+-28Input+Record+Separator-29]:
  \Set `$/` (input record separator).
- {Option -a}[options_md.html#label-a-3A+Split+Input+Lines+into+Fields]:
  Split input lines into fields.
- {Option -F}[options_md.html#label-F-3A+Set+Input+Field+Separator]:
  \Set input field separator.
- {Option -l}[options_md.html#label-l-3A+Set+Output+Record+Separator-3B+Chop+Lines]:
  \Set output record separator; chop lines.
- {Option -p}[options_md.html#label-p-3A+-n-2C+with+Printing]:
  `-n`, with printing.

### `-p`: `-n`, with Printing

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

See also:

- {Option -0}[options_md.html#label-0-3A+Set+-24-2F+-28Input+Record+Separator-29]:
  \Set `$/` (input record separator).
- {Option -a}[options_md.html#label-a-3A+Split+Input+Lines+into+Fields]:
  Split input lines into fields.
- {Option -F}[options_md.html#label-F-3A+Set+Input+Field+Separator]:
  \Set input field separator.
- {Option -l}[options_md.html#label-l-3A+Set+Output+Record+Separator-3B+Chop+Lines]:
  \Set output record separator; chop lines.
- {Option -n}[options_md.html#label-n-3A+Run+Program+in+gets+Loop]:
  Run program in `gets` loop.

### `-r`: Require Library

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

### `-s`: Define Global Variable

Option `-s` specifies that a "custom option" is to define a global variable
in the invoked Ruby program:

- The custom option must appear _after_ the program name.
- The custom option must begin with single hyphen (e.g., `-foo`),
  not two hyphens (e.g., `--foo`).
- The name of the global variable is based on the option name:
  global variable `$foo` for custom option`-foo`.
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

The option may not be used with
{option -e}[options_md.html#label-e-3A+Execute+Given+Ruby+Code]

### `-S`: Search Directories in `ENV['PATH']`

Option `-S` specifies that the Ruby interpreter
is to search (if necessary) the directories whose paths are in the program's
`PATH` environment variable;
the program is executed in the shell's current working directory
(not necessarily in the directory where the program is found).

This example uses adds path `'tmp/'` to the `PATH` environment variable:

```sh
$ export PATH=/tmp:$PATH
$ echo "puts File.basename(Dir.pwd)" > /tmp/t.rb
$ ruby -S t.rb
ruby
```

### `-v`: Print Version; \Set `$VERBOSE`

Options `-v` prints the Ruby version and sets global variable `$VERBOSE`:

```
$ ruby -e 'p $VERBOSE'
false
$ ruby -v -e 'p $VERBOSE'
ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [x64-mingw-ucrt]
true
```

### `-w`: Synonym for `-W1`

Option `-w` (lowercase letter) is equivalent to option `-W1` (uppercase letter).

### `-W`: \Set \Warning Policy

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

### `-x`: Execute Ruby Code Found in Text

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

If an argument is given, it must immediately follow the option
(no intervening whitespace or equal-sign character `'='`).

### `--backtrace-limit`: \Set Backtrace Limit

Option `--backtrace-limit` sets a limit on the number of entries
to be displayed in a backtrace.

See Thread::Backtrace.limit.

### `--copyright`: Print Ruby Copyright

Option `--copyright` prints a copyright message:

```sh
$ ruby --copyright
ruby - Copyright (C) 1993-2021 Yukihiro Matsumoto
```

### `--debug`: Alias for `-d`

Option `--debug` is an alias for
{option -d}[options_md.html#label-d-3A+Set+-24DEBUG+to+true].

### `--disable`: Disable Features

Option `--disable` specifies features to be disabled;
the argument is a comma-separated list of the features to be disabled:

```sh
ruby --disable=gems,rubyopt t.rb
```

The supported features:

- `gems`: Rubygems (default: enabled).
- `did_you_mean`: `did_you_mean` (default: enabled).
- `rubyopt`: `RUBYOPT` environment variable (default: enabled).
- `frozen-string-literal`: Freeze all string literals (default: disabled).
- `jit`: JIT compiler (default: disabled).

See also {option --enable}[options_md.html#label--enable-3A+Enable+Features].

### `--dump`: Dump Items

Option `--dump` specifies items to be dumped;
the argument is a comma-separated list of the items.

Some of the argument values cause the command to behave as if a different
option was given:

- `--dump=copyright`:
  Same as {option \-\-copyright}[options_md.html#label--copyright-3A+Print+Ruby+Copyright].
- `--dump=help`:
  Same as {option \-\-help}[options_md.html#label--help-3A+Print+Help+Message].
- `--dump=syntax`:
  Same as {option -c}[options_md.html#label-c-3A+Check+Syntax].
- `--dump=usage`:
  Same as {option -h}[options_md.html#label-h-3A+Print+Short+Help+Message].
- `--dump=version`:
  Same as {option \-\-version}[options_md.html#label--version-3A+Print+Ruby+Version].

For the remaining argument values, we use this program:

```sh
$ cat t.rb
puts 'Foo'
```

The supported items:

- `insns`: Instruction sequences:

    ```sh
    $ ruby --dump=insns t.rb
    == disasm: #<ISeq:<main>@t.rb:1 (1,0)-(1,10)> (catch: FALSE)
    0000 putself                                                          (   1)[Li]
    0001 putstring                              "Foo"
    0003 opt_send_without_block                 <calldata!mid:puts, argc:1, FCALL|ARGS_SIMPLE>
    0005 leave
    ```

- `parsetree`: {Abstract syntax tree}[https://en.wikipedia.org/wiki/Abstract_syntax_tree]
  (AST):

    ```sh
    $ ruby --dump=parsetree t.rb
    ###########################################################
    ## Do NOT use this node dump for any purpose other than  ##
    ## debug and research.  Compatibility is not guaranteed. ##
    ###########################################################

    # @ NODE_SCOPE (line: 1, location: (1,0)-(1,10))
    # +- nd_tbl: (empty)
    # +- nd_args:
    # |   (null node)
    # +- nd_body:
    #     @ NODE_FCALL (line: 1, location: (1,0)-(1,10))*
    #     +- nd_mid: :puts
    #     +- nd_args:
    #         @ NODE_LIST (line: 1, location: (1,5)-(1,10))
    #         +- nd_alen: 1
    #         +- nd_head:
    #         |   @ NODE_STR (line: 1, location: (1,5)-(1,10))
    #         |   +- nd_lit: "Foo"
    #         +- nd_next:
    #             (null node)
    ```

- `parsetree_with_comment`: AST with comments:

    ```sh
    $ ruby --dump=parsetree_with_comment t.rb
    ###########################################################
    ## Do NOT use this node dump for any purpose other than  ##
    ## debug and research.  Compatibility is not guaranteed. ##
    ###########################################################

    # @ NODE_SCOPE (line: 1, location: (1,0)-(1,10))
    # | # new scope
    # | # format: [nd_tbl]: local table, [nd_args]: arguments, [nd_body]: body
    # +- nd_tbl (local table): (empty)
    # +- nd_args (arguments):
    # |   (null node)
    # +- nd_body (body):
    #     @ NODE_FCALL (line: 1, location: (1,0)-(1,10))*
    #     | # function call
    #     | # format: [nd_mid]([nd_args])
    #     | # example: foo(1)
    #     +- nd_mid (method id): :puts
    #     +- nd_args (arguments):
    #         @ NODE_LIST (line: 1, location: (1,5)-(1,10))
    #         | # list constructor
    #         | # format: [ [nd_head], [nd_next].. ] (length: [nd_alen])
    #         | # example: [1, 2, 3]
    #         +- nd_alen (length): 1
    #         +- nd_head (element):
    #         |   @ NODE_STR (line: 1, location: (1,5)-(1,10))
    #         |   | # string literal
    #         |   | # format: [nd_lit]
    #         |   | # example: 'foo'
    #         |   +- nd_lit (literal): "Foo"
    #         +- nd_next (next element):
    #             (null node)
    ```

- `yydebug`: Debugging information from yacc parser generator:

    ```sh
    $ ruby --dump=yydebug t.rb
    Starting parse
    Entering state 0
    Reducing stack by rule 1 (line 1295):
    lex_state: NONE -> BEG at line 1296
    vtable_alloc:12392: 0x0000558453df1a00
    vtable_alloc:12393: 0x0000558453df1a60
    cmdarg_stack(push): 0 at line 12406
    cond_stack(push): 0 at line 12407
    -> $$ = nterm $@1 (1.0-1.0: )
    Stack now 0
    Entering state 2
    Reading a token:
    lex_state: BEG -> CMDARG at line 9049
    Next token is token "local variable or method" (1.0-1.4: puts)
    Shifting token "local variable or method" (1.0-1.4: puts)
    Entering state 35
    Reading a token: Next token is token "string literal" (1.5-1.6: )
    Reducing stack by rule 742 (line 5567):
    $1 = token "local variable or method" (1.0-1.4: puts)
    -> $$ = nterm operation (1.0-1.4: )
    Stack now 0 2
    Entering state 126
    Reducing stack by rule 78 (line 1794):
    $1 = nterm operation (1.0-1.4: )
    -> $$ = nterm fcall (1.0-1.4: )
    Stack now 0 2
    Entering state 80
    Next token is token "string literal" (1.5-1.6: )
    Reducing stack by rule 292 (line 2723):
    cmdarg_stack(push): 1 at line 2737
    -> $$ = nterm $@16 (1.4-1.4: )
    Stack now 0 2 80
    Entering state 235
    Next token is token "string literal" (1.5-1.6: )
    Shifting token "string literal" (1.5-1.6: )
    Entering state 216
    Reducing stack by rule 607 (line 4706):
    -> $$ = nterm string_contents (1.6-1.6: )
    Stack now 0 2 80 235 216
    Entering state 437
    Reading a token: Next token is token "literal content" (1.6-1.9: "Foo")
    Shifting token "literal content" (1.6-1.9: "Foo")
    Entering state 503
    Reducing stack by rule 613 (line 4802):
    $1 = token "literal content" (1.6-1.9: "Foo")
    -> $$ = nterm string_content (1.6-1.9: )
    Stack now 0 2 80 235 216 437
    Entering state 507
    Reducing stack by rule 608 (line 4716):
    $1 = nterm string_contents (1.6-1.6: )
    $2 = nterm string_content (1.6-1.9: )
    -> $$ = nterm string_contents (1.6-1.9: )
    Stack now 0 2 80 235 216
    Entering state 437
    Reading a token:
    lex_state: CMDARG -> END at line 7276
    Next token is token "terminator" (1.9-1.10: )
    Shifting token "terminator" (1.9-1.10: )
    Entering state 508
    Reducing stack by rule 590 (line 4569):
    $1 = token "string literal" (1.5-1.6: )
    $2 = nterm string_contents (1.6-1.9: )
    $3 = token "terminator" (1.9-1.10: )
    -> $$ = nterm string1 (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 109
    Reducing stack by rule 588 (line 4559):
    $1 = nterm string1 (1.5-1.10: )
    -> $$ = nterm string (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 108
    Reading a token:
    lex_state: END -> BEG at line 9200
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 586 (line 4541):
    $1 = nterm string (1.5-1.10: )
    -> $$ = nterm strings (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 107
    Reducing stack by rule 307 (line 2837):
    $1 = nterm strings (1.5-1.10: )
    -> $$ = nterm primary (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 90
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 261 (line 2553):
    $1 = nterm primary (1.5-1.10: )
    -> $$ = nterm arg (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 220
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 270 (line 2586):
    $1 = nterm arg (1.5-1.10: )
    -> $$ = nterm arg_value (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 221
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 297 (line 2779):
    $1 = nterm arg_value (1.5-1.10: )
    -> $$ = nterm args (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 224
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 772 (line 5626):
    -> $$ = nterm none (1.10-1.10: )
    Stack now 0 2 80 235 224
    Entering state 442
    Reducing stack by rule 296 (line 2773):
    $1 = nterm none (1.10-1.10: )
    -> $$ = nterm opt_block_arg (1.10-1.10: )
    Stack now 0 2 80 235 224
    Entering state 441
    Reducing stack by rule 288 (line 2696):
    $1 = nterm args (1.5-1.10: )
    $2 = nterm opt_block_arg (1.10-1.10: )
    -> $$ = nterm call_args (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 453
    Reducing stack by rule 293 (line 2723):
    $1 = nterm $@16 (1.4-1.4: )
    $2 = nterm call_args (1.5-1.10: )
    cmdarg_stack(pop): 0 at line 2754
    -> $$ = nterm command_args (1.4-1.10: )
    Stack now 0 2 80
    Entering state 333
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 79 (line 1804):
    $1 = nterm fcall (1.0-1.4: )
    $2 = nterm command_args (1.4-1.10: )
    -> $$ = nterm command (1.0-1.10: )
    Stack now 0 2
    Entering state 81
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 73 (line 1770):
    $1 = nterm command (1.0-1.10: )
    -> $$ = nterm command_call (1.0-1.10: )
    Stack now 0 2
    Entering state 78
    Reducing stack by rule 51 (line 1659):
    $1 = nterm command_call (1.0-1.10: )
    -> $$ = nterm expr (1.0-1.10: )
    Stack now 0 2
    Entering state 75
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 39 (line 1578):
    $1 = nterm expr (1.0-1.10: )
    -> $$ = nterm stmt (1.0-1.10: )
    Stack now 0 2
    Entering state 73
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 8 (line 1354):
    $1 = nterm stmt (1.0-1.10: )
    -> $$ = nterm top_stmt (1.0-1.10: )
    Stack now 0 2
    Entering state 72
    Reducing stack by rule 5 (line 1334):
    $1 = nterm top_stmt (1.0-1.10: )
    -> $$ = nterm top_stmts (1.0-1.10: )
    Stack now 0 2
    Entering state 71
    Next token is token '\n' (1.10-1.10: )
    Shifting token '\n' (1.10-1.10: )
    Entering state 311
    Reducing stack by rule 769 (line 5618):
    $1 = token '\n' (1.10-1.10: )
    -> $$ = nterm term (1.10-1.10: )
    Stack now 0 2 71
    Entering state 313
    Reducing stack by rule 770 (line 5621):
    $1 = nterm term (1.10-1.10: )
    -> $$ = nterm terms (1.10-1.10: )
    Stack now 0 2 71
    Entering state 314
    Reading a token: Now at end of input.
    Reducing stack by rule 759 (line 5596):
    $1 = nterm terms (1.10-1.10: )
    -> $$ = nterm opt_terms (1.10-1.10: )
    Stack now 0 2 71
    Entering state 312
    Reducing stack by rule 3 (line 1321):
    $1 = nterm top_stmts (1.0-1.10: )
    $2 = nterm opt_terms (1.10-1.10: )
    -> $$ = nterm top_compstmt (1.0-1.10: )
    Stack now 0 2
    Entering state 70
    Reducing stack by rule 2 (line 1295):
    $1 = nterm $@1 (1.0-1.0: )
    $2 = nterm top_compstmt (1.0-1.10: )
    vtable_free:12426: p->lvtbl->args(0x0000558453df1a00)
    vtable_free:12427: p->lvtbl->vars(0x0000558453df1a60)
    cmdarg_stack(pop): 0 at line 12428
    cond_stack(pop): 0 at line 12429
    -> $$ = nterm program (1.0-1.10: )
    Stack now 0
    Entering state 1
    Now at end of input.
    Shifting token "end-of-input" (1.10-1.10: )
    Entering state 3
    Stack now 0 1 3
    Cleanup: popping token "end-of-input" (1.10-1.10: )
    Cleanup: popping nterm program (1.0-1.10: )
    ```

### `--enable`: Enable Features

Option `--enable` specifies features to be enabled;
the argument is a comma-separated list of the features to be enabled.

```sh
ruby --enable=gems,rubyopt t.rb
```

For the features,
see {option --disable}[options_md.html#label--disable-3A+Disable+Features].

### `--encoding`: Alias for `-E`.

Option `--encoding` is an alias for
{option -E}[options_md.html#label-E-3A+Set+Default+Encodings].

### `--external-encoding`: \Set Default External \Encoding

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

### `--help`: Print Help Message

Option `--help` prints a long help message.

Arguments and additional options are ignored.

For a shorter help message, use option `-h`.

### `--internal-encoding`: \Set Default Internal \Encoding

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

### `--verbose`: \Set `$VERBOSE`

Option `--verbose` sets global variable `$VERBOSE` to `true`
and disables input from `$stdin`.

### `--version`: Print Ruby Version

Option `--version` prints the version of the Ruby interpreter, then exits.

## Experimental Options

These options are experimental in the current Ruby release,
and may be modified or withdrawn in later releases.

### `--jit`

Option `-jit` enables JIT compilation with the default option.

#### `--jit-debug`

Option `--jit-debug` enables JIT debugging (very slow);
adds compiler flags if given.

#### `--jit-max-cache=num`

Option `--jit-max-cache=num` sets the maximum number of methods
to be JIT-ed in a cache; default: 100).

#### `--jit-min-calls=num`

Option `jit-min-calls=num` sets the minimum number of calls to trigger JIT
(for testing); default: 10000).

#### `--jit-save-temps`

Option `--jit-save-temps` saves JIT temporary files in $TMP or /tmp (for testing).

#### `--jit-verbose`

Option `--jit-verbose` prints JIT logs of level `num` or less
to `$stderr`; default: 0.

#### `--jit-wait`

Option `--jit-wait` waits until JIT compilation finishes every time (for testing).

#### `--jit-warnings`

Option `--jit-warnings` enables printing of JIT warnings.

