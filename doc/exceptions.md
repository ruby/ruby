# Exceptions

Ruby code can raise exceptions.

Most often, a raised exception is meant to alert the running program
that an unusual (i.e., _exceptional_) situation has arisen,
and may need to be handled.

Code throughout the Ruby core, Ruby standard library, and Ruby gems generates exceptions
in certain circumstances:

```
File.open('nope.txt') # Raises Errno::ENOENT: "No such file or directory"
```

## Raised Exceptions

A raised exception transfers program execution, one way or another.

### Unrescued Exceptions

If an exception not _rescued_
(see [Rescued Exceptions](#label-Rescued+Exceptions) below),
execution transfers to code in the Ruby interpreter
that prints a message and exits the program (or thread):

```
$ ruby -e "raise"
-e:1:in `<main>': unhandled exception
```

### Rescued Exceptions

An <i>exception handler</i> may determine what is to happen
when an exception is raised;
the handler may _rescue_ an exception,
and may prevent the program from exiting.

A simple example:

```
begin
  raise 'Boom!'                # Raises an exception, transfers control.
  puts 'Will not get here.'
rescue
  puts 'Rescued an exception.' # Control tranferred to here; program does not exit.
end
puts 'Got here.'
```

Output:

```
Rescued an exception.
Got here.
```

An exception handler has several elements:

| Element                     | Use                                                                                      |
|-----------------------------|------------------------------------------------------------------------------------------|
| Begin clause.               | Begins the handler and contains the code whose raised exception, if any, may be rescued. |
| One or more rescue clauses. | Each contains "rescuing" code, which is to be executed for certain exceptions.           |
| Else clause (optional).     | Contains code to be executed if no exception is raised.                                  |
| Ensure clause (optional).   | Contains code to be executed whether or not an exception is raised, or is rescued.       |
| <tt>end</tt> statement.     | Ends the handler.  `                                                                     |

#### Begin Clause

The begin clause begins the exception handler:

- May start with a `begin` statement;
  see also [Begin-Less Exception Handlers](#label-Begin-Less+Exception+Handlers).
- Contains code whose raised exception (if any) is covered
  by the handler.
- Ends with the first following `rescue` statement.

#### Rescue Clauses

A rescue clause:

- Starts with a `rescue` statement.
- Contains code that is to be executed for certain raised exceptions.
- Ends with the first following `rescue`,
  `else`, `ensure`, or `end` statement.

##### Rescued Exceptions

A `rescue` statement may include one or more classes
that are to be rescued;
if none is given, StandardError is assumed.

The rescue clause rescues both the specified class
(or StandardError if none given) or any of its subclasses;
see [Built-In Exception Class Hierarchy](rdoc-ref:Exception@Built-In+Exception+Class+Hierarchy).

```
begin
  1 / 0 # Raises ZeroDivisionError, a subclass of StandardError.
rescue
  puts "Rescued #{$!.class}"
end
```

Output:

```
Rescued ZeroDivisionError
```

If the `rescue` statement specifies an exception class,
only that class (or one of its subclasses) is rescued;
this example exits with a ZeroDivisionError,
which was not rescued because it is not ArgumentError or one of its subclasses:

```
begin
  1 / 0
rescue ArgumentError
  puts "Rescued #{$!.class}"
end
```

A `rescue` statement may specify multiple classes,
which means that its code rescues an exception
of any of the given classes (or their subclasses):

```
begin
  1 / 0
rescue FloatDomainError, ZeroDivisionError
  puts "Rescued #{$!.class}"
end
```

##### Multiple Rescue Clauses

An exception handler may contain multiple rescue clauses;
in that case, the first clause that rescues the exception does so,
and those before and after are ignored:

```
begin
  Dir.open('nosuch')
rescue Errno::ENOTDIR
  puts "Rescued #{$!.class}"
rescue Errno::ENOENT
  puts "Rescued #{$!.class}"
end
```

Output:

```
Rescued Errno::ENOENT
```

##### Capturing the Rescued \Exception

A `rescue` statement may specify a variable
whose value becomes the rescued exception
(an instance of Exception or one of its subclasses:

```
begin
  1 / 0
rescue => x
  puts x.class
  puts x.message
end
```

Output:

```
ZeroDivisionError
divided by 0
```

##### Global Variables

Two read-only global variables always have `nil` value
except in a rescue clause;
there:

- `$!`: contains the rescued exception.
- `$@`: contains its backtrace.

Example:

```
begin
  1 / 0
rescue => x
  puts $!.__id__ == x.__id__
  puts $@.__id__ == x.backtrace.__id__
end
```

Output:

```
true
true
```

##### Cause

In a rescue clause, the method Exception#cause returns the previous value of `$!`,
which may be `nil`;
elsewhere, the method returns `nil`.

Example:

```
begin
  raise('Boom 0')
rescue => x0
  puts "Exception: #{x0.inspect};  $!: #{$!.inspect};  cause: #{x0.cause.inspect}."
  begin
    raise('Boom 1')
  rescue => x1
    puts "Exception: #{x1.inspect};  $!: #{$!.inspect};  cause: #{x1.cause.inspect}."
    begin
      raise('Boom 2')
    rescue => x2
      puts "Exception: #{x2.inspect};  $!: #{$!.inspect};  cause: #{x2.cause.inspect}."
    end
  end
end
```

Output:

```
Exception: #<RuntimeError: Boom 0>;  $!: #<RuntimeError: Boom 0>;  cause: nil.
Exception: #<RuntimeError: Boom 1>;  $!: #<RuntimeError: Boom 1>;  cause: #<RuntimeError: Boom 0>.
Exception: #<RuntimeError: Boom 2>;  $!: #<RuntimeError: Boom 2>;  cause: #<RuntimeError: Boom 1>.
```

#### Else Clause

The `else` clause:

- Starts with an `else` statement.
- Contains code that is to be executed if no exception is raised in the begin clause.
- Ends with the first following `ensure` or `end` statement.

```
begin
  puts 'Begin.'
rescue
  puts 'Rescued an exception!'
else
  puts 'No exception raised.'
end
```

Output:

```
Begin.
No exception raised.
```

#### Ensure Clause

The ensure clause:

- Starts with an `ensure` statement.
- Contains code that is to be executed
  regardless of whether an exception is raised,
  and regardless of whether a raised exception is handled.
- Ends with the first following `end` statement.

```
def foo(boom: false)
  puts 'Begin.'
  raise 'Boom!' if boom
rescue
  puts 'Rescued an exception!'
else
  puts 'No exception raised.'
ensure
  puts 'Always do this.'
end

foo(boom: true)
foo(boom: false)
```

Output:

```
Begin.
Rescued an exception!
Always do this.
Begin.
No exception raised.
Always do this.
```

#### End Statement

The `end` statement ends the handler.

Code following it is reached only if any raised exception is rescued.

#### Begin-Less \Exception Handlers

As seen above, an exception handler may be implemented with `begin` and `end`.

An exception handler may also be implemented as:

- A method body:

    ```
    def foo(boom: false) # Serves as beginning of exception handler.
      puts 'Begin.'
      raise 'Boom!' if boom
    rescue
      puts 'Rescued an exception!'
    else
      puts 'No exception raised.'
    end                  # Serves as end of exception handler.
    ```

- A block:

    ```
    Dir.chdir('.') do |dir| # Serves as beginning of exception handler.
      raise 'Boom!'
    rescue
      puts 'Rescued an exception!'
    end                     # Serves as end of exception handler.
    ```

#### Re-Raising an \Exception

It can be useful to rescue an exception, but allow its eventual effect;
for example, a program can rescue an exception, log data about it,
and then "reinstate" the exception.

This may be done via the `raise` method, but in a special way;
a rescuing clause:

  - Captures an exception.
  - Does whatever is needed concerning the exception (such as logging it).
  - Calls method `raise` with no argument,
    which raises the rescued exception:

```
begin
  1 / 0
rescue ZeroDivisionError
  # Do needful things (like logging).
  raise # Raised exception will be ZeroDivisionError, not RuntimeError.
end
```

Output:

```
ruby t.rb
t.rb:2:in `/': divided by 0 (ZeroDivisionError)
        from t.rb:2:in `<main>'
```

#### Retrying

It can be useful to retry a begin clause;
for example, if it must access a possibly-volatile resource
(such as a web page),
it can be useful to try the access more than once
(in the hope that it may become available):

```
retries = 0
begin
  puts "Try ##{retries}."
  raise 'Boom'
rescue
  puts "Rescued retry ##{retries}."
  if (retries += 1) < 3
    puts 'Retrying'
    retry
  else
    puts 'Giving up.'
    raise
  end
end
```

```
Try #0.
Rescued retry #0.
Retrying
Try #1.
Rescued retry #1.
Retrying
Try #2.
Rescued retry #2.
Giving up.
# RuntimeError ('Boom') raised.
```

Note that the retry re-executes the entire begin clause,
not just the part after the point of failure.

## Raising an \Exception

\Method Kernel#raise raises an exception.

## Custom Exceptions

To provide additional or alternate information,
you may create custom exception classes.
Each should be a subclass of one of the built-in exception classes
(commonly StandardError or RuntimeError);
see [Built-In Exception Class Hierarchy](rdoc-ref:Exception@Built-In+Exception+Class+Hierarchy).

```
class MyException < StandardError; end
```

## Messages

Every `Exception` object has a message,
which is a string that is set at the time the object is created;
see Exception.new.

The message cannot be changed, but you can create a similar object with a different message;
see Exception#exception.

This method returns the message as defined:

- Exception#message.

Two other methods return enhanced versions of the message:

- Exception#detailed_message: adds exception class name, with optional highlighting.
- Exception#full_message: adds exception class name and backtrace, with optional highlighting.

Each of the two methods above accepts keyword argument `highlight`;
if the value of keyword `highlight` is true (not `nil` or `false`),
the returned string includes bolding and underlining ANSI codes (see below)
to enhance the appearance of the message.

Any exception class (Ruby or custom) may choose to override either of these methods,
and may choose to interpret keyword argument <tt>highlight: true</tt>
to mean that the returned message should contain
[ANSI codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
that specify color, bolding, and underlining).

Because the enhanced message may be written to a non-terminal device
(e.g., into an HTML page),
it is best to limit the ANSI codes to these widely-supported codes:

- Begin font color:

    | Color   | ANSI Code        |
    |---------|------------------|
    | Red     | <tt>\\e[31m</tt> |
    | Green   | <tt>\\e[32m</tt> |
    | Yellow  | <tt>\\e[33m</tt> |
    | Blue    | <tt>\\e[34m</tt> |
    | Magenta | <tt>\\e[35m</tt> |
    | Cyan    | <tt>\\e[36m</tt> |

<br>

- Begin font attribute:

    | Attribute | ANSI Code       |
    |-----------|-----------------|
    | Bold      | <tt>\\e[1m</tt> |
    | Underline | <tt>\\e[4m</tt> |

<br>

- End all of the above:

    | Color | ANSI Code       |
    |-------|-----------------|
    | Reset | <tt>\\e[0m</tt> |

It's also best to craft a message that is conveniently human-readable,
even if the ANSI codes are included "as-is"
(rather than interpreted as font directives).

## Backtraces

A _backtrace_ is a record of the methods currently
in the [call stack](https://en.wikipedia.org/wiki/Call_stack);
each such method has been called, but has not yet returned.

These methods return backtrace information:

- Exception#backtrace: returns the backtrace as an array of strings or `nil`.
- Exception#backtrace_locations: returns the backtrace as an array
  of Thread::Backtrace::Location objects or `nil`.
  Each Thread::Backtrace::Location object gives detailed information about a called method.

An `Exception` object stores its backtrace value as one of:

- An array of Thread::Backtrace::Location objects;
  this is the case for an exception raised by the Ruby core or the Ruby standard library.
  In this case:

    - Exception#backtrace_locations returns the array of Thread::Backtrace::Location objects.
    - Exception#backtrace returns the array of their string values
      (`Exception#backtrace_locations.map {|loc| loc.to_s }`).

- An array of strings;
  in this case:

    - Exception#backtrace returns the array of strings.
    - Exception#backtrace_locations returns `nil`.

- `nil`, in which case both methods return `nil`.

These methods set the backtrace value:

- Exception#set_backtrace: sets the backtrace value to an array of strings, or to `nil`.
- Kernel#raise: sets the backtrace value to an array of Thread::Backtrace::Location objects,
  or to an array of strings.

