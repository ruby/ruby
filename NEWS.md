# NEWS for Ruby 2.8.0 (tentative; to be 3.0.0)

This document is a list of user visible feature changes
since the **2.7.0** release, except for bug fixes.

Note that each entry is kept so brief that no reason behind or reference
information is supplied with.  For a full list of changes with all
sufficient information, see the ChangeLog file or Redmine
(e.g. `https://bugs.ruby-lang.org/issues/$FEATURE_OR_BUG_NUMBER`).

## Language changes

* Keyword arguments are now separated from positional arguments.
  Code that resulted in deprecation warnings in Ruby 2.7 will now
  result in ArgumentError or different behavior. [[Feature #14183]]

* $SAFE is now a normal global variable with no special behavior.
  [[Feature #16131]]

* yield in singleton class definitions in methods is now a SyntaxError
  instead of a warning. yield in a class definition outside of a method
  is now a SyntaxError instead of a LocalJumpError.  [[Feature #15575]]

## Command line options

## Core classes updates

Outstanding ones only.

* Dir

    * Modified method

        * Dir.glob and Dir.[] now sort the results by default, and
          accept `sort:` keyword option.  [[Feature #8709]]

* Hash

    * Modified method

        * Hash#transform_keys now accepts a hash that maps keys to new
          keys.  [[Feature #16274]]

* Kernel

    * Modified method

        * Kernel#clone when called with `freeze: false` keyword will call
          #initialize_clone with the `freeze: false` keyword.
          [[Bug #14266]]

        * Kernel#eval when called with two arguments will use "(eval)"
          for `__FILE__` and 1 for `__LINE__` in the evaluated code.
          [[Bug #4352]]

* Module

    * Modified method

        * Module#include now includes the arguments in modules and
          classes that have already included or prepended the receiver,
          mirroring the behavior if the arguments were included in the
          receiver before the other modules and classes included or
          prepended the receiver.  [[Feature #9573]]

* Symbol

    * Modified method

        * Symbol#to_proc now returns a lambda Proc.
          [[Feature #16260]]

## Stdlib updates

Outstanding ones only.

* Net::HTTP

    * New method

        * Add Net::HTTP#verify_hostname= and Net::HTTP#verify_hostname
          to skip hostname verification.  [[Feature #16555]]

## Compatibility issues

Excluding feature bug fixes.

* Regexp literals are frozen [[Feature #8948]] [[Feature #16377]]

    ```ruby
    /foo/.frozen? #=> true
    ```

* Bundled gems

    * net-telnet and xmlrpc have been removed from the bundled gems.
      If you are interested in maintaining them, please comment on
      your plan to https://github.com/ruby/xmlrpc
      or https://github.com/ruby/net-telnet.

## Stdlib compatibility issues

Excluding feature bug fixes.

## C API updates

* C API functions related to $SAFE have been removed.
  [[Feature #16131]]

## Implementation improvements

## Miscellaneous changes

* Methods using `ruby2_keywords` will no longer keep empty keyword
  splats, those are now removed just as they are for methods not
  using `ruby2_keywords`.

* Taint deprecation warnings are now issued in regular mode in
  addition to verbose warning mode.  [[Feature #16131]]


[Bug #4352]:      https://bugs.ruby-lang.org/issues/4352
[Feature #8709]:  https://bugs.ruby-lang.org/issues/8709
[Feature #8948]:  https://bugs.ruby-lang.org/issues/8948
[Feature #9573]:  https://bugs.ruby-lang.org/issues/9573
[Feature #14183]: https://bugs.ruby-lang.org/issues/14183
[Bug #14266]:     https://bugs.ruby-lang.org/issues/14266
[Feature #15575]: https://bugs.ruby-lang.org/issues/15575
[Feature #16131]: https://bugs.ruby-lang.org/issues/16131
[Feature #16260]: https://bugs.ruby-lang.org/issues/16260
[Feature #16274]: https://bugs.ruby-lang.org/issues/16274
[Feature #16377]: https://bugs.ruby-lang.org/issues/16377
[Feature #16555]: https://bugs.ruby-lang.org/issues/16555
