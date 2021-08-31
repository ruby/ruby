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

* Pin operator now supports instance, class, and global variables.
  [[Feature #17724]]

    ```ruby
    @n = 5
    Prime.each_cons(2).lazy.find{_1 in [n, ^@n]}
    #=> [3, 5]
    ```

* One-line pattern matching is no longer experimental.

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

* Integer

    * Integer.try_convert is added. [[Feature #15211]]

* Module

    * Module#prepend now modifies the ancestor chain if the receiver
      already includes the argument. Module#prepend still does not
      modify the ancestor chain if the receiver has already prepended
      the argument. [[Bug #17423]]

* Struct

    * Passing only keyword arguments to Struct#initialize is warned.
      You need to use a Hash literal to set a Hash to a first member.
      [[Feature #16806]]

    * StructClass#keyword_init? is added [[Feature #18008]]

* String

    * Update Unicode version to 13.0.0 [[Feature #17750]]
      and Emoji version to 13.0 [[Feature #18029]]

* Queue

    * Queue#initialize now accepts an Enumerable of initial values.
      [[Feature #17327]]

* Thread

    * Thread#native_thread_id is added. [[Feature #17853]]

* Thread::Backtrace

    * Thread::Backtrace.limit, which returns the value to limit backtrace
      length set by `--backtrace-limit` command line option, is added.
      [[Feature #17479]]

* $LOAD_PATH

    * $LOAD_PATH.resolve_feature_path does not raise. [[Feature #16043]]

* Fiber Scheduler

    * Add support for `Addrinfo.getaddrinfo` using `address_resolve` hook.
      [[Feature #17370]]

    * Introduce non-blocking `Timeout.timeout` using `timeout_after` hook.
      [[Feature #17470]]

    * IO hooks `io_wait`, `io_read`, `io_write`, receive the original IO object
      where possible. [[Bug #18003]]

    * Make `Monitor` fiber-safe. [[Bug #17827]]

    * Replace copy coroutine with pthread implementation. [[Feature #18015]]

## Stdlib updates

Outstanding ones only.

## Compatibility issues

Excluding feature bug fixes.

* `rb_io_wait_readable`, `rb_io_wait_writable` and `rb_wait_for_single_fd` are
  deprecated in favour of `rb_io_maybe_wait_readable`,
  `rb_io_maybe_wait_writable` and `rb_io_maybe_wait` respectively.
  `rb_thread_wait_fd` and `rb_thread_fd_writable` are deprecated. [[Bug #18003]]

## Stdlib compatibility issues

* `ERB#initialize` warns `safe_level` and later arguments even without -w.
  [[Feature #14256]]

## C API updates

## Implementation improvements

### JIT

* The default `--jit-max-cache` is changed from 100 to 10000.

* JIT-ed code is no longer cancelled when a TracePoint for class events
  is enabled.

* The JIT compiler no longer skips compilation of methods longer than
  1000 instructions.

* `--jit-verbose` and `--jit-warning` output "JIT cancel" when JIT-ed
  code is disabled because TracePoint or GC.compact is used.

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
  [[Feature #17762]]

* Now exceptions raised in finalizers will be printed to `STDERR`, unless
  `$VERBOSE` is `nil`.  [[Feature #17798]]

[Bug #4443]:      https://bugs.ruby-lang.org/issues/4443
[Feature #12194]: https://bugs.ruby-lang.org/issues/12194
[Feature #14256]: https://bugs.ruby-lang.org/issues/14256
[Feature #15198]: https://bugs.ruby-lang.org/issues/15198
[Feature #15211]: https://bugs.ruby-lang.org/issues/15211
[Feature #16043]: https://bugs.ruby-lang.org/issues/16043
[Feature #16806]: https://bugs.ruby-lang.org/issues/16806
[Feature #17312]: https://bugs.ruby-lang.org/issues/17312
[Feature #17327]: https://bugs.ruby-lang.org/issues/17327
[Feature #17411]: https://bugs.ruby-lang.org/issues/17411
[Bug #17423]:     https://bugs.ruby-lang.org/issues/17423
[Feature #17479]: https://bugs.ruby-lang.org/issues/17479
[Feature #17490]: https://bugs.ruby-lang.org/issues/17490
[Feature #17724]: https://bugs.ruby-lang.org/issues/17724
[Feature #17744]: https://bugs.ruby-lang.org/issues/17744
[Feature #17762]: https://bugs.ruby-lang.org/issues/17762
[Feature #17798]: https://bugs.ruby-lang.org/issues/17798
[Bug #18003]:     https://bugs.ruby-lang.org/issues/18003
[Feature #17370]: https://bugs.ruby-lang.org/issues/17370
[Feature #17470]: https://bugs.ruby-lang.org/issues/17470
[Feature #17750]: https://bugs.ruby-lang.org/issues/17750
[Feature #17853]: https://bugs.ruby-lang.org/issues/17853
[Bug #17827]:     https://bugs.ruby-lang.org/issues/17827
[Feature #18008]: https://bugs.ruby-lang.org/issues/18008
[Feature #18015]: https://bugs.ruby-lang.org/issues/18015
[Feature #18029]: https://bugs.ruby-lang.org/issues/18029
