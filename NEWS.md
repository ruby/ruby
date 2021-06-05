# NEWS for Ruby 3.1.0

This document is a list of user visible feature changes
since the **3.0.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* Pin operator now takes an expression. [[Feature #17411]]

    ```ruby
    Prime.each_cons(2).lazy.find_all{_1 in [n, ^(n + 2)]}.take(3).to_a
    #=> [[3, 5], [5, 7], [11, 13]]
    ```

* Multiple assignment evaluation order has been made consistent with
  single assignment evaluation order.  With single assignment, Ruby
  uses a left-to-right evaluation order.  With this code:

    ```ruby
    foo[0] = bar
    ```

  The following evaluation order is used:

  1. `foo`
  2. `bar`
  3. `[]=` called on the result of `foo`

  In Ruby before 3.1.0, multiple assignment did not follow this
  evaluation order.  With this code:

    ```ruby
    foo[0], bar.baz = a, b
    ```

  Versions of Ruby before 3.1.0 would evaluate in the following
  order

  1. `a`
  2. `b`
  3. `foo`
  4. `[]=` called on the result of `foo`
  5. `bar`
  6. `baz=` called on the result of `bar`

  Starting in Ruby 3.1.0, evaluation order is now consistent with
  single assignment, with the left hand side being evaluated before
  the right hand side:

  1. `foo`
  2. `bar`
  3. `a`
  4. `b`
  5. `[]=` called on the result of `foo`
  6. `baz=` called on the result of `bar`

  [[Bug #4443]]

## Command line options

## Core classes updates

Outstanding ones only.

* Array

    * Array#intersect? is added. [[Feature #15198]]

* Enumerable

    * Enumerable#compact is added. [[Feature #17312]]

    * Enumerable#tally now accepts an optional hash to count. [[Feature #17744]]

* Enumerator::Lazy

    * Enumerator::Lazy#compact is added. [[Feature #17312]]

* File

    * File.dirname now accepts an optional argument for the level to
      strip path components. [[Feature #12194]]

* Module

    * Module#prepend now modifies the ancestor chain if the receiver
      already includes the argument. Module#prepend still does not
      modify the ancestor chain if the receiver has already prepended
      the argument. [[Bug #17423]]

* Struct

    * Passing only keyword arguments to Struct#initialize is warned.
      You need to use a Hash literal to set a Hash to a first member.
      [[Feature #16806]]

* Queue

    * Queue#initialize now accepts an Enumerable of initial values.
      [[Feature #17327]]

* Thread

    * Thread#native_thread_id is added. [[Feature #17853]]

* Thread::Backtrace

    * Thread::Backtrace.limit, which returns the value to limit backtrace
      length set by `--backtracse-limit` command line option, is added.
      [[Feature #17479]]

* $LOAD_PATH

    * $LOAD_PATH.resolve_feature_path does not raise. [[Feature #16043]]

## Stdlib updates

Outstanding ones only.

## Compatibility issues

Excluding feature bug fixes.

## Stdlib compatibility issues

* `ERB#initialize` warns `safe_level` and later arguments even without -w.
  [[Feature #14256]]

## C API updates

## Implementation improvements

### JIT

* The default `--jit-max-cache` is changed from 100 to 10000.

* The JIT compiler no longer skips compilation of methods longer than
  1000 instructions.

* `RubyVM::MJIT` is renamed to `RubyVM::JIT`. [[Feature #17490]]

## Static analysis

### RBS

### TypeProf

## Miscellaneous changes

* lib/objspace/trace.rb is added, which is a tool for tracing the object
  allocation. Just by requiring this file, tracing is started *immediately*.
  Just by `Kernel#p`, you can investigate where an object was created.
  Note that just requiring this file brings a large performance overhead.
  This is only for debugging purpose. Do not use this in production.
  [Feature #17762]

[Bug #4443]: https://bugs.ruby-lang.org/issues/4443
[Feature #12194]: https://bugs.ruby-lang.org/issues/12194
[Feature #14256]: https://bugs.ruby-lang.org/issues/14256
[Feature #15198]: https://bugs.ruby-lang.org/issues/15198
[Feature #16043]: https://bugs.ruby-lang.org/issues/16043
[Feature #16806]: https://bugs.ruby-lang.org/issues/16806
[Feature #17312]: https://bugs.ruby-lang.org/issues/17312
[Feature #17327]: https://bugs.ruby-lang.org/issues/17327
[Feature #17411]: https://bugs.ruby-lang.org/issues/17411
[Bug #17423]: https://bugs.ruby-lang.org/issues/17423
[Feature #17479]: https://bugs.ruby-lang.org/issues/17479
[Feature #17490]: https://bugs.ruby-lang.org/issues/17490
[Feature #17744]: https://bugs.ruby-lang.org/issues/17744
[Feature #17762]: https://bugs.ruby-lang.org/issues/17762
