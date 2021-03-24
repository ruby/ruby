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

## Command line options

## Core classes updates

Outstanding ones only.

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

* `RubyVM::MJIT` is renamed to `RubyVM::JIT`.

## Static analysis

### RBS

### TypeProf

## Miscellaneous changes


[Feature #12194]: https://bugs.ruby-lang.org/issues/12194
[Feature #14256]: https://bugs.ruby-lang.org/issues/14256
[Feature #16043]: https://bugs.ruby-lang.org/issues/16043
[Feature #16806]: https://bugs.ruby-lang.org/issues/16806
[Feature #17312]: https://bugs.ruby-lang.org/issues/17312
[Feature #17327]: https://bugs.ruby-lang.org/issues/17327
[Feature #17411]: https://bugs.ruby-lang.org/issues/17411
[Bug #17423]: https://bugs.ruby-lang.org/issues/17423
[Feature #17479]: https://bugs.ruby-lang.org/issues/17479
[Feature #17744]: https://bugs.ruby-lang.org/issues/17744
