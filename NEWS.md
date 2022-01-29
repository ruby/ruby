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

* Constant assignment evaluation order for constants set on explicit
  objects has been made consistent with single attribute assignment
  evaluation order.  With this code:

    ```ruby
    foo::BAR = baz
    ```

  `foo` is now called before `baz`. Similarly, for multiple assignment
  to constants,  left-to-right evaluation order is used.  With this
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

## Command line options

## Core classes updates

Note: We're only listing outstanding class updates.

* Hash
    * Hash#shift now always returns nil if the hash is
      empty, instead of returning the default value or
      calling the default proc. [[Bug #16908]]

* Module
    * Module.used_refinements has been added. [[Feature #14332]]
    * Module#refinements has been added. [[Feature #12737]]
    * Module#const_added has been added. [[Feature #17881]]

* Proc
    * Proc#dup returns an instance of subclass. [[Bug #17545]]

* Refinement
    * Refinement#refined_class has been added. [[Feature #12737]]

* Struct
    * A Struct class can also be initialized with keyboard arguments
      without `keyword_init: true` on `Struct.new` [[Feature #16806]]

## Stdlib updates

*   The following default gem are updated.
    * RubyGems 3.4.0.dev
    * bigdecimal 3.1.2
    * bundler 2.4.0.dev
    * etc 1.4.0
    * io-console 0.5.11
    * reline 0.3.1
*   The following bundled gems are updated.
    * net-imap 0.2.3
    * typeprof 0.21.2
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

## C API updates

### Removed C APIs

The following deprecated APIs are removed.

* `rb_cData` variable.
* "taintedness" and "trustedness" functions. [[Feature #16131]]

## Implementation improvements

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
[Feature #12737]: https://bugs.ruby-lang.org/issues/12737
[Feature #14332]: https://bugs.ruby-lang.org/issues/14332
[Feature #15231]: https://bugs.ruby-lang.org/issues/15231
[Bug #15928]:     https://bugs.ruby-lang.org/issues/15928
[Feature #16131]: https://bugs.ruby-lang.org/issues/16131
[Feature #16806]: https://bugs.ruby-lang.org/issues/16806
[Bug #16908]:     https://bugs.ruby-lang.org/issues/16908
[Feature #17351]: https://bugs.ruby-lang.org/issues/17351
[Feature #17391]: https://bugs.ruby-lang.org/issues/17391
[Bug #17545]:     https://bugs.ruby-lang.org/issues/17545
[Feature #17881]: https://bugs.ruby-lang.org/issues/17881
[Feature #18351]: https://bugs.ruby-lang.org/issues/18351
