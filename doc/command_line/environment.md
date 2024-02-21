## Environment

Certain command-line options affect the execution environment
of the invoked Ruby program.

### About the Examples

The examples here use command-line option `-e`,
which passes the Ruby code to be executed on the command line itself:

```sh
$ ruby -e 'puts "Hello, World."'
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

### Option `-I`

The argument to option `-I` specifies a directory
to be added to the array in global variable `$LOAD_PATH`;
the option may be given more than once:

```sh
$ pushd C:/
$ ruby -e 'p $LOAD_PATH.size'
8
$ $ ruby -I my_lib -I some_lib -e 'p $LOAD_PATH.size; p $LOAD_PATH[0..1]'
10
["C:/my_lib", "C:/some_lib"]
$ popd
```

Whitespace between the option and its argument may be omitted.

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

### Option `-0`

Option `-0` defines the input record separator `$/`
for the invoked Ruby program.

The optional argument to the option must be octal digits,
each in the range `0..7`;
these digits are prefixed with digit `0` to form an octal value:

- If that value is in range `(0..0377)`,
  it becomes the character value of the input record separator `$/`.
- Otherwise, the input record separator is `nil`.

If no argument is given, the input record separator is `0x00`.

Examples:

```sh
$ ruby -0 -e 'p $/'
"\x00"
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

### Option '-w'

Option `-w` (lowercase letter) is equivalentto option `-W1` (uppercase letter).

### Option `-W`

Ruby code can create a <i>warning message</i> by calling method Kernel#warn;
this may cause a message to be printed on `$stderr`
(or not, depending on certain settings).

Option `-W` helps determine whether a particular warning message
will be written,
by setting the initial value of environment variable `$-W`:

- `-W0`: Sets `$-W` to `0` (silent; no warnings).
- `-W1`: Sets `$-W` to `1` (moderate verbosity).
- `-W2`: Sets `$-W` to `2` (high verbosity).
- `-W`: Same as `-W2` (high verbosity).
- Option not given: Same as `-W1` (moderate verbosity).

The value of `$-W`, in turn, determines which warning messages (if any)
are to be printed to `$stdout` (see Kernel#warn):

```sh
$ ruby -W0 -e 'p $-W; p IO::Buffer.new' # Silent; no warning message.
0
#<IO::Buffer>
$ ruby -W1 -e 'p $-W; p IO::Buffer.new'
1
-e:1: warning: IO::Buffer is experimental and both the Ruby and C interface may change in the future!
#<IO::Buffer>
$ ruby -W2 -e 'p $-W; p IO::Buffer.new'
2
-e:1: warning: IO::Buffer is experimental and both the Ruby and C interface may change in the future!
#<IO::Buffer>
```

Note
: Some of the examples above elicit level-1 warning messages
  from the experimental method `IO::Buffer.new`
  as it exists in Ruby version 3.3.0;
  that method (being experimental) may not work the same way in other versions of Ruby.

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

See also {Field Processing}[rdoc-ref:command_line/field_processing.md].
