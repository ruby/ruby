# NEWS for Ruby 3.3.0

This document is a list of user-visible feature changes
since the **3.2.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

## Command line options

* A new `performance` warning category was introduced.
  They are not displayed by default even in verbose mode.
  Turn them on with `-W:performance` or `Warning[:performance] = true`. [[Feature #19538]]
* The `RUBY_GC_HEAP_INIT_SLOTS` environment variable has been deprecated and
  removed. Environment variables `RUBY_GC_HEAP_%d_INIT_SLOTS` should be
  used instead.  [[Feature #19785]]

## Core classes updates

Note: We're only listing outstanding class updates.

* Array

    * Array#pack now raises ArgumentError for unknown directives. [[Bug #19150]]

* Dir

    * Dir.for_fd added for returning a Dir object for the directory specified
      by the provided directory file descriptor. [[Feature #19347]]
    * Dir.fchdir added for changing the directory to the directory specified
      by the provided directory file descriptor. [[Feature #19347]]
    * Dir#chdir added for changing the directory to the directory specified by
      the provided `Dir` object. [[Feature #19347]]

* MatchData

    * MatchData#named_captures now accepts optional `symbolize_names`
      keyword. [[Feature #19591]]

* Module

    * Module#set_temporary_name added for setting a temporary name for a
      module. [[Feature #19521]]

* ObjectSpace::WeakKeyMap

    * New core class to build collections with weak references.
      The class use equality semantic to lookup keys like a regular hash,
      but it doesn't hold strong references on the keys. [[Feature #18498]]

* Proc
    * Now Proc#dup and Proc#clone call `#initialize_dup` and `#initialize_clone`
      hooks respectively.  [[Feature #19362]]

* Process.warmup

    * Notify the Ruby virtual machine that the boot sequence is finished,
      and that now is a good time to optimize the application. This is useful
      for long running applications. The actual optimizations performed are entirely
      implementation specific and may change in the future without notice. [[Feature #18885]]

* Process::Status

    * Process::Status#& and Process::Status#>> are deprecated. [[Bug #19868]]

* Range

    * Range#reverse_each can now process beginless ranges with an Integer endpoint. [[Feature #18515]]

* Refinement

    * Add Refinement#target as an alternative of Refinement#refined_class.
      Refinement#refined_class is deprecated and will be removed in Ruby
      3.4.  [[Feature #19714]]

* String

    * String#unpack now raises ArgumentError for unknown directives. [[Bug #19150]]
    * String#bytesplice now accepts new arguments index/length or range of the
      source string to be copied.  [[Feature #19314]]

## Stdlib updates

* RubyGems and Bundler warn if users require gem that is scheduled to become the bundled gems
  in the future version of Ruby. [[Feature #19351]] [[Feature #19776]] [[Feature #19843]]

  Targeted libraries are:
    * abbrev
    * base64
    * bigdecimal
    * csv
    * drb
    * getoptlong
    * mutex_m
    * nkf
    * observer
    * resolv-replace
    * rinda
    * syslog

* Socket#recv and Socket#recv_nonblock returns `nil` instead of an empty string on closed
  connections. Socket#recvmsg and Socket#recvmsg_nonblock returns `nil` instead of an empty packet on closed
  connections. [[Bug #19012]]

* Random::Formatter#alphanumeric is extended to accept optional `chars`
  keyword argument. [[Feature #18183]]

The following default gem is added.

* prism 0.15.1

The following default gems are updated.

* RubyGems 3.5.0.dev
* bigdecimal 3.1.5
* bundler 2.5.0.dev
* csv 3.2.8
* erb 4.0.3
* fiddle 1.1.2
* fileutils 1.7.1
* io-console 0.6.1.dev
* irb 1.8.3
* nkf 0.1.3
* openssl 3.2.0
* optparse 0.4.0.pre.1
* psych 5.1.1.1
* reline 0.3.9
* stringio 3.0.9
* strscan 3.0.7
* syntax_suggest 1.1.0
* time 0.2.2
* timeout 0.4.0
* uri 0.12.2

The following bundled gem is promoted from default gems.

* racc 1.7.1

The following bundled gems are updated.

* minitest 5.20.0
* test-unit 3.6.1
* rexml 3.2.6
* rss 0.3.0
* net-imap 0.4.1
* net-smtp 0.4.0
* rbs 3.2.2
* typeprof 0.21.8
* debug 1.8.0

See GitHub releases like [Logger](https://github.com/ruby/logger/releases) or
changelog for details of the default gems or bundled gems.

## Supported platforms

## Compatibility issues

## Stdlib compatibility issues

* `racc` is promoted to bundled gems.
  * You need to add `racc` to your `Gemfile` if you use `racc` under bundler environment.
* `ext/readline` is retired
  * We have `reline` that is pure Ruby implementation compatible with `ext/readline` API. We rely on `reline` in the future. If you need to use `ext/readline`, you can install `ext/readline` via rubygems.org with `gem install readline-ext`.
  * We no longer need to install libraries like `libreadline` or `libedit`.

## C API updates

## Implementation improvements

* `defined?(@ivar)` is optimized with Object Shapes.

### YJIT

* Major performance improvements over 3.2
  * Support for splat and rest arguments has been improved.
  * Registers are allocated for stack operations of the virtual machine.
  * More calls with optional arguments are compiled.
  * Exception handlers are also compiled.
  * Instance variables no longer exit to the interpreter
    with megamorphic object shapes.
  * Unsupported call types no longer exit to the interpreter.
  * `Integer#!=`, `String#!=`, `Kernel#block_given?`, `Kernel#is_a?`,
    `Kernel#instance_of?`, `Module#===` are specially optimized.
  * Now more than 3x faster than the interpreter on optcarrot!
* Significantly improved memory usage over 3.2
    * Metadata for compiled code uses a lot less memory.
    * Generate more compact code on ARM64
* Compilation speed is now slightly faster than 3.2.
* Add `RubyVM::YJIT.enable` that can enable YJIT later
  * You can start YJIT without modifying command-line arguments or environment variables.
  * This can also be used to enable YJIT only once your application is
    done booting. `--yjit-disable` can be used if you want to use other
    YJIT options while disabling YJIT at boot.
* Option to disable code GC and treat `--yjit-exec-mem-size` as a hard limit
  * Can produce better copy-on-write behavior on servers using unicorn and forking
* `ratio_in_yjit` stat produced by `--yjit-stats` is now avaiable in release builds,
  a special stats or dev build is no longer required to access most stats.
* Exit tracing option now supports sampling
  * `--trace-exits-sample-rate=N`
* More thorough testing and multiple bug fixes
* `--yjit-stats=quiet` is added to avoid printing stats on exit.
* `--yjit-perf` is added to facilitate profiling with Linux perf.

### MJIT

* MJIT is removed.
  * `--disable-jit-support` is removed. Consider using `--disable-yjit --disable-rjit` instead.

### RJIT

* Introduced a pure-Ruby JIT compiler RJIT.
  * RJIT supports only x86\_64 architecture on Unix platforms.
  * Unlike MJIT, it doesn't require a C compiler at runtime.
* RJIT exists only for experimental purposes.
  * You should keep using YJIT in production.

[Feature #18183]: https://bugs.ruby-lang.org/issues/18183
[Feature #18498]: https://bugs.ruby-lang.org/issues/18498
[Feature #18515]: https://bugs.ruby-lang.org/issues/18515
[Feature #18885]: https://bugs.ruby-lang.org/issues/18885
[Bug #19012]:     https://bugs.ruby-lang.org/issues/19012
[Bug #19150]:     https://bugs.ruby-lang.org/issues/19150
[Feature #19314]: https://bugs.ruby-lang.org/issues/19314
[Feature #19347]: https://bugs.ruby-lang.org/issues/19347
[Feature #19351]: https://bugs.ruby-lang.org/issues/19351
[Feature #19362]: https://bugs.ruby-lang.org/issues/19362
[Feature #19521]: https://bugs.ruby-lang.org/issues/19521
[Feature #19538]: https://bugs.ruby-lang.org/issues/19538
[Feature #19591]: https://bugs.ruby-lang.org/issues/19591
[Feature #19714]: https://bugs.ruby-lang.org/issues/19714
[Feature #19776]: https://bugs.ruby-lang.org/issues/19776
[Feature #19785]: https://bugs.ruby-lang.org/issues/19785
[Feature #19843]: https://bugs.ruby-lang.org/issues/19843
[Bug #19868]:     https://bugs.ruby-lang.org/issues/19868
