# NEWS for Ruby 3.2.0

This document is a list of user-visible feature changes
since the **3.1.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* Anonymous rest and keyword rest arguments can now be passed as
  arguments, instead of just used in method parameters.
  [[Feature #18351]]

    ```ruby
    def foo(*)
      bar(*)
    end
    def baz(**)
      quux(**)
    end
    ```

* A proc that accepts a single positional argument and keywords will
  no longer autosplat. [[Bug #18633]]

  ```ruby
  proc{|a, **k| a}.call([1, 2])
  # Ruby 3.1 and before
  # => 1
  # Ruby 3.2 and after
  # => [1, 2]
  ```

* Constant assignment evaluation order for constants set on explicit
  objects has been made consistent with single attribute assignment
  evaluation order. With this code:

    ```ruby
    foo::BAR = baz
    ```

  `foo` is now called before `baz`. Similarly, for multiple assignments
  to constants,  left-to-right evaluation order is used. With this
  code:

    ```ruby
      foo1::BAR1, foo2::BAR2 = baz1, baz2
    ```

  The following evaluation order is now used:

  1. `foo1`
  2. `foo2`
  3. `baz1`
  4. `baz2`

  [[Bug #15928]]

* Find pattern is no longer experimental.
  [[Feature #18585]]

* Methods taking a rest parameter (like `*args`) and wishing to delegate keyword
  arguments through `foo(*args)` must now be marked with `ruby2_keywords`
  (if not already the case). In other words, all methods wishing to delegate
  keyword arguments through `*args` must now be marked with `ruby2_keywords`,
  with no exception. This will make it easier to transition to other ways of
  delegation once a library can require Ruby 3+. Previously, the `ruby2_keywords`
  flag was kept if the receiving method took `*args`, but this was a bug and an
  inconsistency. A good technique to find the potentially-missing `ruby2_keywords`
  is to run the test suite, for where it fails find the last method which must
  receive keyword arguments, use `puts nil, caller, nil` there, and check each
  method/block on the call chain which must delegate keywords is correctly marked
  as `ruby2_keywords`. [[Bug #18625]] [[Bug #16466]]

    ```ruby
    def target(**kw)
    end

    # Accidentally worked without ruby2_keywords in Ruby 2.7-3.1, ruby2_keywords
    # needed in 3.2+. Just like (*args, **kwargs) or (...) would be needed on
    # both #foo and #bar when migrating away from ruby2_keywords.
    ruby2_keywords def bar(*args)
      target(*args)
    end

    ruby2_keywords def foo(*args)
      bar(*args)
    end

    foo(k: 1)
    ```

## Command line options

## Core classes updates

Note: We're only listing outstanding class updates.

* Hash
    * Hash#shift now always returns nil if the hash is
      empty, instead of returning the default value or
      calling the default proc. [[Bug #16908]]

* Kernel
    * Kernel#binding raises RuntimeError if called from a non-Ruby frame
      (such as a method defined in C). [[Bug #18487]]

* MatchData
    * MatchData#byteoffset has been added. [[Feature #13110]]

* Module
    * Module.used_refinements has been added. [[Feature #14332]]
    * Module#refinements has been added. [[Feature #12737]]
    * Module#const_added has been added. [[Feature #17881]]
    * Module#undefined_instance_methods has been added. [[Feature #12655]]

* Proc
    * Proc#dup returns an instance of subclass. [[Bug #17545]]
    * Proc#parameters now accepts lambda keyword. [[Feature #15357]]

* Regexp
    * Regexp.new now supports passing the regexp flags not only as an Integer,
      but also as a String Unknown flags raise errors.  Otherwise, anything
      other than `true`, `false`, `nil` or Integer will be warned.
      [[Feature #18788]]

* Refinement
    * Refinement#refined_class has been added. [[Feature #12737]]

* Set
    * Set is now available as a built-in class without the need for `require "set"`. [[Feature #16989]]
      It is currently autoloaded via the `Set` constant or a call to `Enumerable#to_set`.

* String
    * String#byteindex and String#byterindex have been added. [[Feature #13110]]
    * Update Unicode to Version 14.0.0 and Emoji Version 14.0. [[Feature #18037]]
      (also applies to Regexp)
    * String#bytesplice has been added.  [[Feature #18598]]

* Struct
    * A Struct class can also be initialized with keyword arguments
      without `keyword_init: true` on `Struct.new` [[Feature #16806]]

* TracePoint
    * TracePoint#binding now returns `nil` for `c_call`/`c_return` TracePoints.
      [[Bug #18487]]
    * TracePoint#enable `target_thread` keyword argument now defaults to the
      current thread if `target` and `target_line` keyword arguments are not
      passed. [[Bug #16889]]

## Stdlib updates

*   The following default gems are updated.
    * RubyGems 3.4.0.dev
    * bigdecimal 3.1.2
    * bundler 2.4.0.dev
    * cgi 0.3.2
    * etc 1.4.0
    * io-console 0.5.11
    * io-nonblock 0.1.1
    * io-wait 0.2.3
    * ipaddr 1.2.4
    * json 2.6.2
    * logger 1.5.1
    * net-http 0.2.2
    * net-protocol 0.1.3
    * ostruct 0.5.5
    * psych 5.0.0.dev
    * reline 0.3.1
    * securerandom 0.2.0
    * stringio 3.0.3
    * timeout 0.3.0
*   The following bundled gems are updated.
    * minitest 5.16.1
    * net-imap 0.2.3
    * rbs 2.5.1
    * typeprof 0.21.2
    * debug 1.5.0
*   The following default gems are now bundled gems.

## Compatibility issues

Note: Excluding feature bug fixes.

### Removed constants

The following deprecated constants are removed.

* `Fixnum` and `Bignum` [[Feature #12005]]
* `Random::DEFAULT` [[Feature #17351]]
* `Struct::Group`
* `Struct::Passwd`

### Removed methods

The following deprecated methods are removed.

* `Dir.exists?` [[Feature #17391]]
* `File.exists?` [[Feature #17391]]
* `Kernel#=~` [[Feature #15231]]
* `Kernel#taint`, `Kernel#untaint`, `Kernel#tainted?`
  [[Feature #16131]]
* `Kernel#trust`, `Kernel#untrust`, `Kernel#untrusted?`
  [[Feature #16131]]

## Stdlib compatibility issues

* `Psych` no longer bundles libyaml sources.
  Users need to install the libyaml library themselves via the package
  system. [[Feature #18571]]

## C API updates

### Removed C APIs

The following deprecated APIs are removed.

* `rb_cData` variable.
* "taintedness" and "trustedness" functions. [[Feature #16131]]

## Implementation improvements

* Fixed several race conditions in `Kernel#autoload`. [[Bug #18782]]

## JIT

### MJIT

### YJIT: New experimental in-process JIT compiler

## Static analysis

### RBS

### TypeProf

## Debugger

## error_highlight

## IRB Autocomplete and Document Display

## Miscellaneous changes

[Feature #12005]: https://bugs.ruby-lang.org/issues/12005
[Feature #12655]: https://bugs.ruby-lang.org/issues/12655
[Feature #12737]: https://bugs.ruby-lang.org/issues/12737
[Feature #13110]: https://bugs.ruby-lang.org/issues/13110
[Feature #14332]: https://bugs.ruby-lang.org/issues/14332
[Feature #15231]: https://bugs.ruby-lang.org/issues/15231
[Feature #15357]: https://bugs.ruby-lang.org/issues/15357
[Bug #15928]:     https://bugs.ruby-lang.org/issues/15928
[Feature #16131]: https://bugs.ruby-lang.org/issues/16131
[Bug #16466]:     https://bugs.ruby-lang.org/issues/16466
[Feature #16806]: https://bugs.ruby-lang.org/issues/16806
[Bug #16889]:     https://bugs.ruby-lang.org/issues/16889
[Bug #16908]:     https://bugs.ruby-lang.org/issues/16908
[Feature #16989]: https://bugs.ruby-lang.org/issues/16989
[Feature #17351]: https://bugs.ruby-lang.org/issues/17351
[Feature #17391]: https://bugs.ruby-lang.org/issues/17391
[Bug #17545]:     https://bugs.ruby-lang.org/issues/17545
[Feature #17881]: https://bugs.ruby-lang.org/issues/17881
[Feature #18037]: https://bugs.ruby-lang.org/issues/18037
[Feature #18351]: https://bugs.ruby-lang.org/issues/18351
[Bug #18487]:     https://bugs.ruby-lang.org/issues/18487
[Feature #18571]: https://bugs.ruby-lang.org/issues/18571
[Feature #18585]: https://bugs.ruby-lang.org/issues/18585
[Feature #18598]: https://bugs.ruby-lang.org/issues/18598
[Bug #18625]:     https://bugs.ruby-lang.org/issues/18625
[Bug #18633]:     https://bugs.ruby-lang.org/issues/18633
[Bug #18782]:     https://bugs.ruby-lang.org/issues/18782
[Feature #18788]: https://bugs.ruby-lang.org/issues/18788
