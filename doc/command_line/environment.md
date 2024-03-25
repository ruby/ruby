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

