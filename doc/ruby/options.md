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

### Option `-0`

Option `-0` defines the input record separator `$/`
for the invoked Ruby program.

The optional argument to the option must be octal digits,
each in the range `0..7`;
these digits are prefixed with digit `0` to form an octal value:

- If no argument is given, the input record separator is `0x00`.
- If the argument is `0`, the input record separator is `''`;
  see {Special Line Separator Values}[rdoc-ref:IO@Special+Line+Separator+Values].
- If the argument is in range `(1..0377)`,
  it becomes the character value of the input record separator `$/`.
- Otherwise, the input record separator is `nil`.

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

The option may not be separated from its argument by whitespace.

### Option `-a`

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

### Option `-c`

Option `-c` specifies that the specified Ruby program
should be checked for syntax, but not actually executed:

```
$ ruby -e 'puts "Foo"'
Foo
$ ruby -c -e 'puts "Foo"'
Syntax OK
```

### Option `-C`

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

### Option `-d`

Some code in (or called by) the Ruby program may include statements or blocks
conditioned by the global variable `$DEBUG` (e.g., `if $DEBUG`);
these commonly write to `$stdout` or `$stderr`.

The default value for `$DEBUG` is `false`;
option `-d` (or `--debug`) sets it to `true`:

```sh
$ ruby -e 'p $DEBUG'
false
$ ruby -d -e 'p $DEBUG'
true
```

### Option `-e`

Option `-e` requires an argument, which is Ruby code to be executed;
the option may be given more than once:

```
$ ruby -e 'puts "Foo"' -e 'puts "Bar"'
Foo
Bar
```

The command should not include arguments (which, if given, are ignored).

Whitespace between the option and its argument may be omitted.

### Option `-E`

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

### Option `-F`

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

### Option `-i`

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

### Option `-I`

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

### Option `-jit` TODO

### Option `-l`

Option `-l`, when given with option `-n` or `-p`,
modifies line-ending processing by:

- Setting global variable output record separator `$\`
  input record separator `$/`;
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

### Option `-n`

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

### Option `-p`

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

### Option `-r`

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

### Option `-s`

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

### Option `-S` TODO

### Option `-v`

Options `-v` prints the Ruby version and sets global variable `$VERBOSE`:

```
$ ruby -e 'p $VERBOSE'
false
$ ruby -v -e 'p $VERBOSE'
ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [x64-mingw-ucrt]
true
```

### Option `-w`

Option `-w` (lowercase letter) is equivalent to option `-W1` (uppercase letter).

### Option `-W`

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

### Option `-x` TODO

