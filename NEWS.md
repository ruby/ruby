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

* Procs accepting a single rest argument and keywords are no longer
  subject to autosplatting.  This now matches the behavior of Procs
  accepting a single rest argument and no keywords.
  [[Feature #16166]]

    ```ruby
    pr = proc{|*a, **kw| [a, kw]}

    pr.call([1])
    # 2.7 => [[1], {}]
    # 3.0 => [[[1]], {}]

    pr.call([1, {a: 1}])
    # 2.7 => [[1], {:a=>1}] # and deprecation warning
    # 3.0 => [[[1, {:a=>1}]], {}]
    ```

* $SAFE is now a normal global variable with no special behavior.
  [[Feature #16131]]

* yield in singleton class definitions in methods is now a SyntaxError
  instead of a warning. yield in a class definition outside of a method
  is now a SyntaxError instead of a LocalJumpError.  [[Feature #15575]]

* Rightward assignment statement is added.  [EXPERIMENTAL]
  [[Feature #15921]]

    ```ruby
    fib(10) => x
    ```

* Endless method definition is added.  [EXPERIMENTAL]
  [[Feature #16746]]

    ```ruby
    def square(x) = x * x
    ```

## Command line options

### `--help` option

When the environment variable `RUBY_PAGER` or `PAGER` is present and has
non-empty value, and the standard input and output are tty, `--help`
option shows the help message via the pager designated by the value.
[[Feature #16754]]

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

    * Modified method

        * Net::HTTP.get, Net::HTTP.get_response, and Net::HTTP.get_print can
          take request headers as a Hash in the second argument when the first
          argument is a URI.

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

* EXPERIMENTAL: Hash#each consistently yields a 2-element array [[Bug #12706]]

    * Now `{ a: 1 }.each(&->(k, v) { })` raises an ArgumentError
      due to lambda's arity check.
    * This is experimental; if it brings a big incompatibility issue,
      it may be reverted until 2.8/3.0 release.

* When writing to STDOUT redirected to a closed pipe, SignalException
  is raised now instead of Errno::EPIPE, so that no broken pipe error
  message will be shown.  [[Feature #14413]]

## Stdlib compatibility issues

Excluding feature bug fixes.

## C API updates

* C API functions related to $SAFE have been removed.
  [[Feature #16131]]

* C API header file `ruby/ruby.h` was split. [[GH-2991]] Should have no implact
  on extension libraries, but users might experience slow compilations.

## Implementation improvements

* The number of hashes allocated when using a keyword splat in
  a method call has been reduced to a maximum of 1, and passing
  a keyword splat to a method that accepts specific keywords
  does not allocate a hash.

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
[Feature #14413]: https://bugs.ruby-lang.org/issues/14413
[Feature #15575]: https://bugs.ruby-lang.org/issues/15575
[Feature #16131]: https://bugs.ruby-lang.org/issues/16131
[Feature #16166]: https://bugs.ruby-lang.org/issues/16166
[Feature #16260]: https://bugs.ruby-lang.org/issues/16260
[Feature #16274]: https://bugs.ruby-lang.org/issues/16274
[Feature #16377]: https://bugs.ruby-lang.org/issues/16377
[Bug #12706]:     https://bugs.ruby-lang.org/issues/12706
[Feature #15921]: https://bugs.ruby-lang.org/issues/15921
[Feature #16555]: https://bugs.ruby-lang.org/issues/16555
[Feature #16746]: https://bugs.ruby-lang.org/issues/16746
[Feature #16754]: https://bugs.ruby-lang.org/issues/16754
[GH-2991]:        https://github.com/ruby/ruby/pull/2991
