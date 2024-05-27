# Exceptions

Any Ruby code can raise an exception.

Most often, a raised exception is meant to alert the running program
that an unusual (i.e., _exceptional_) situation has arisen,
and may need to be handled.

Code throughout the Ruby core, Ruby standard library, and Ruby gems generates exceptions
in certain circumstances:

```
File.open('nope.txt') # Raises Errno::ENOENT: "No such file or directory"
```

# Raised Exceptions

A raised exception transfers program execution, one way or another.

## Unhandled Exceptions

If an exception is _unhandled_
(see [Exception Handlers](#label-Exception+Handlers) below),
execution transfers to code in the Ruby interpreter
that prints a message and exits the program (or thread):

```
$ ruby -e "raise"
-e:1:in `<main>': unhandled exception
```

## \Exception Handlers

An <i>exception handler</i> may determine what is to happen
when an exception is raised.

A simple example:

```
begin
  raise 'Boom!'                # Raises an exception, transfers control.
  puts 'Will not get here.'
rescue
  puts 'Rescued an exception.' # Control tranferred to here.
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
| Else clause (optional).     | Contains code to be executed if no exception is rescued.                                 |
| Ensure clause (optional).   | Contains code to be executed whether or not an exception is raised, or is rescued.       |
| <tt>end</tt> statement.     | Ends the handler.  `                                                                     |

### Begin Clause

The begin clause begins the exception handler:

- May start with a `begin` statement;
  see also [Begin-Less Exception Handlers](#label-Begin-Less+Exception+Handlers).
- Contains code whose raised exception (if any) is covered
  by the handler.
- Ends with the first following `rescue` statement.

### Rescue Clauses

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

A `rescue` statement may specify a variable;
in that case, the rescued exception
(an instance of Exception or one of its subclasses)
is assigned to that variable:

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


### Else Clause

The `else` clause:

- Starts with an `else` statement.
- Contains code that is to be executed if no exception is handled in the rescue clauses.
- Ends with the first following `ensure` or `end` statement.

```
def foo(boom: false)
  puts 'Begin.'
  raise 'Boom!' if boom
rescue
  puts 'Rescued an exception!'
else
  puts 'No exception raised.'
end

foo(boom: true)
foo(boom: false)
```

Output:

```
Begin.
Rescued an exception!
Begin.
No exception raised.
```

### Ensure Clause

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

### End Statement

The `end` statement ends the handler.

Code following it is reached if and only if any raised exception is handled
and not [re-raised](#label-Re-Raising+an+Exception).

### Begin-Less \Exception Handlers

As seen above, an exception handler may be implemented with `begin` and `end`.

An exception handler may also be implemented
(without separate `begin` and `end` statements)
as a:

- \Method body:

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

- Block:

    ```
    Dir.chdir('.') do |dir| # Serves as beginning of exception handler.
      raise 'Boom!'
    rescue
      puts 'Rescued an exception!'
    end                     # Serves as end of exception handler.
    ```

### Re-Raising an \Exception

### Retrying

# Raising Exceptions

# Custom Exceptions
