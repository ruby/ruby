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

A `rescue` statement may include one or more classes
that are to be rescued;
if none is given, StandardError is assumed.

The rescue clause rescues both the specified class
(or StandardError if none given) or any of its subclasses;
(see [Built-In Exception Classes](rdoc-ref:Exception@Built-In+Exception+Classes)
for the hierarchy of Ruby built-in exception classes):


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

In the rescue clause, these global variables are defined:

- `$!`": the current exception instance.
- `$@`: its backtrace.

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

Raise an exception with method Kernel#raise.

## Custom Exceptions

To provide additional or alternate information,
you may create custom exception classes;
each should be a subclass of one of the built-in exception classes.

If you are building a library or gem (or even if you're not),
it's good practice to start with a single “generic” exception class
(commonly an immediate subclass of StandardError or RuntimeError),
and have its other exception classes derive from that class.
This allows an exception handler to rescue the generic exception,
thus also rescuing all its derived exceptions.

For example:

```
class MyLib
  class Error < StandardError; end
  class FooError < Error; end
  class BarError < Error; end
end
```

An exception handler rescue clause that rescues `MyLib::Error`
will also rescue the derived classes `MyLib::FooError` and `MyLib::BarError`.
