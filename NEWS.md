# NEWS for Ruby 3.3.0

This document is a list of user-visible feature changes
since the **3.2.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

## Command line options

* A new `performance` warning category was introduced.
  They are not displayed by default even in verbose mode.
  Turn them on with `-W:performance` or `Warning[:performance] = true`. [[Feature #19538]]

## Core classes updates

Note: We're only listing outstanding class updates.

* Array

    * `Array#pack` now raises ArgumentError for unknown directives. [[Bug #19150]]

* Dir

    * `Dir.for_fd` added for returning a Dir object for the directory specified
      by the provided directory file descriptor. [[Feature #19347]]
    * `Dir.fchdir` added for changing the directory to the directory specified
      by the provided directory file descriptor. [[Feature #19347]]
    * `Dir#chdir` added for changing the directory to the directory specified
      by the provided `Dir` object. [[Feature #19347]]

* MatchData

    * MatchData#named_captures now accepts optional `symbolize_names` keyword. [[Feature #19591]]

* String

    * `String#unpack` now raises ArgumentError for unknown directives. [[Bug #19150]]
    * `String#bytesplice` now accepts new arguments index/length or range of the source string to be copied.  [[Feature #19314]]

* ObjectSpace::WeakKeyMap

    * New core class to build collections with weak references.
      The class use equality semantic to lookup keys like a regular hash,
      but it doesn't hold strong references on the keys. [[Feature #18498]]

## Stdlib updates

The following default gems are updated.

* RubyGems 3.5.0.dev
* bigdecimal 3.1.4
* bundler 2.5.0.dev
* csv 3.2.7
* fiddle 1.1.2
* fileutils 1.7.1
* irb 1.6.4
* optparse 0.4.0.pre.1
* psych 5.1.0
* reline 0.3.3
* stringio 3.0.7
* strscan 3.0.7
* syntax_suggest 1.0.4
* time 0.2.2
* timeout 0.3.2
* uri 0.12.1

The following bundled gems are updated.

* minitest 5.18.0
* test-unit 3.5.8
* rbs 3.1.0
* typeprof 0.21.7
* debug 1.8.0

See GitHub releases like [Logger](https://github.com/ruby/logger/releases) or
changelog for details of the default gems or bundled gems.

## Supported platforms

## Compatibility issues

## Stdlib compatibility issues

### `ext/readline` is retired

* We have `reline` that is pure Ruby implementation compatible with `ext/readline` API. We rely on `reline` in the future. If you need to use `ext/readline`, you can install `ext/readline` via rubygems.org with `gem install readline-ext`.
* We no longer need to install libraries like `libreadline` or `libedit`.

## C API updates

## Implementation improvements

* `defined?(@ivar)` is optimized with Object Shapes.

### YJIT

* Significant performance improvements over 3.2
  * Splat and rest arguments support has been improved.
  * Registers are allocated for stack operations of the virtual machine.
  * More calls with optional arguments are compiled.
  * `Integer#!=`, `String#!=`, `Kernel#block_given?`, `Kernel#is_a?`,
    `Kernel#instance_of?`, `Module#===` are specially optimized.
  * Instance variables no longer exit to the interpreter
    with megamorphic Object Shapes.
* Metadata for compiled code uses a lot less memory.
* Improved code generation on ARM64
* Option to start YJIT in paused mode and then later enable it manually
  * `--yjit-pause` and `RubyVM::YJIT.resume`
  * This can be used to enable YJIT only once your application is done booting
* Exit tracing option now supports sampling
  * `--trace-exits-sample-rate=N`
* Multiple bug fixes

### RJIT

* Introduced a pure-Ruby JIT compiler RJIT and replaced MJIT.
  * RJIT supports only x86\_64 architecture on Unix platforms.
  * Unlike MJIT, it doesn't require a C compiler at runtime.
* RJIT exists only for experimental purposes.
  * You should keep using YJIT in production.

[Feature #18498]: https://bugs.ruby-lang.org/issues/18498
[Bug #19150]:     https://bugs.ruby-lang.org/issues/19150
[Feature #19314]: https://bugs.ruby-lang.org/issues/19314
[Feature #19347]: https://bugs.ruby-lang.org/issues/19347
[Feature #19538]: https://bugs.ruby-lang.org/issues/19538
[Feature #19591]: https://bugs.ruby-lang.org/issues/19591
