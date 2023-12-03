# NEWS for Ruby 3.3.0

This document is a list of user-visible feature changes
since the **3.2.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

## Command line options

* A new `performance` warning category was introduced.
  They are not displayed by default even in verbose mode.
  Turn them on with `-W:performance` or `Warning[:performance] = true`. [[Feature #19538]]

* A new `RUBY_CRASH_REPORT` environment variable was introduced to allow
  redirecting Ruby crash reports to a file or sub command. See the `BUG REPORT ENVIRONMENT`
  section of the ruby manpage for further details. [[Feature #19790]]

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

* ObjectSpace::WeakMap

    * `ObjectSpace::WeakMap#delete` was added to eagerly clear weak map
      entries. [[Feature #19561]]

* Proc
    * Now Proc#dup and Proc#clone call `#initialize_dup` and `#initialize_clone`
      hooks respectively.  [[Feature #19362]]

* Process

    * New `Process.warmup` method that notify the Ruby virtual machine that the boot sequence is finished,
      and that now is a good time to optimize the application. This is useful
      for long-running applications. The actual optimizations performed are entirely
      implementation-specific and may change in the future without notice. [[Feature #18885]]

* Process::Status

    * Process::Status#& and Process::Status#>> are deprecated. [[Bug #19868]]

* Queue

    * Queue#freeze now raises TypeError. [[Bug #17146]]

* Range

    * Range#reverse_each can now process beginless ranges with an Integer endpoint. [[Feature #18515]]
    * Range#reverse_each now raises TypeError for endless ranges. [[Feature #18551]]

* Refinement

    * Add Refinement#target as an alternative of Refinement#refined_class.
      Refinement#refined_class is deprecated and will be removed in Ruby
      3.4.  [[Feature #19714]]

* SizedQueue

    * SizedQueue#freeze now raises TypeError. [[Bug #17146]]

* String

    * String#unpack now raises ArgumentError for unknown directives. [[Bug #19150]]
    * String#bytesplice now accepts new arguments index/length or range of the
      source string to be copied.  [[Feature #19314]]

* TracePoint

    * TracePoint supports `rescue` event. When the raised exception was rescued,
      the TracePoint will fire the hook. `rescue` event only supports Ruby-level
      `rescue`. [[Feature #19572]]

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
    * racc
    * resolv-replace
    * rinda
    * syslog

* Socket#recv and Socket#recv_nonblock returns `nil` instead of an empty string on closed
  connections. Socket#recvmsg and Socket#recvmsg_nonblock returns `nil` instead of an empty packet on closed
  connections. [[Bug #19012]]

* Random::Formatter#alphanumeric is extended to accept optional `chars`
  keyword argument. [[Feature #18183]]

The following default gem is added.

* prism 0.18.0

The following default gems are updated.

* RubyGems 3.5.0.dev
* base64 0.2.0
* benchmark 0.3.0
* bigdecimal 3.1.5
* bundler 2.5.0.dev
* cgi 0.4.0
* csv 3.2.8
* date 3.3.4
* delegate 0.3.1
* drb 2.2.0
* english 0.8.0
* erb 4.0.3
* etc 1.4.3.dev.1
* fcntl 1.1.0
* fiddle 1.1.2
* fileutils 1.7.2
* find 0.2.0
* getoptlong 0.2.1
* io-console 0.6.1.dev.1
* irb 1.10.0
* json 2.7.0
* logger 1.6.0
* mutex_m 0.2.0
* net-http 0.4.0
* net-protocol 0.2.2
* nkf 0.1.3
* observer 0.1.2
* open-uri 0.4.0
* open3 0.2.0
* openssl 3.2.0
* optparse 0.4.0
* ostruct 0.6.0
* pathname 0.3.0
* pp 0.5.0
* prettyprint 0.2.0
* pstore 0.1.3
* psych 5.1.1.1
* rdoc 6.6.0
* reline 0.4.0
* rinda 0.2.0
* securerandom 0.3.0
* shellwords 0.2.0
* singleton 0.2.0
* stringio 3.1.1
* strscan 3.0.8
* syntax_suggest 1.1.0
* tempfile 0.2.0
* time 0.3.0
* timeout 0.4.1
* tmpdir 0.2.0
* tsort 0.2.0
* un 0.3.0
* uri 0.13.0
* weakref 0.1.3
* win32ole 1.8.10
* yaml 0.3.0
* zlib 3.1.0

The following bundled gem is promoted from default gems.

* racc 1.7.3

The following bundled gems are updated.

* minitest 5.20.0
* rake 13.1.0
* test-unit 3.6.1
* rexml 3.2.6
* rss 0.3.0
* net-imap 0.4.7
* net-smtp 0.4.0
* rbs 3.3.2
* typeprof 0.21.8
* debug 1.8.0

See GitHub releases like [Logger](https://github.com/ruby/logger/releases) or
changelog for details of the default gems or bundled gems.

## Supported platforms

## Compatibility issues

* Subprocess creation/forking via the following file open methods is deprecated. [[Feature #19630]]
    * Kernel#open
    * URI.open
    * IO.binread
    * IO.foreach
    * IO.readlines
    * IO.read
    * IO.write

* When given a non-lambda, non-literal block, Kernel#lambda with now raises
  ArgumentError instead of returning it unmodified. These usages have been
  issuing warnings under the `Warning[:deprecated]` category since Ruby 3.0.0.
  [[Feature #19777]]

* The `RUBY_GC_HEAP_INIT_SLOTS` environment variable has been deprecated and
  removed. Environment variables `RUBY_GC_HEAP_%d_INIT_SLOTS` should be
  used instead.  [[Feature #19785]]

## Stdlib compatibility issues

* `racc` is promoted to bundled gems.
    * You need to add `racc` to your `Gemfile` if you use `racc` under bundler environment.
* `ext/readline` is retired
    * We have `reline` that is pure Ruby implementation compatible with `ext/readline` API. We rely on `reline` in the future. If you need to use `ext/readline`, you can install `ext/readline` via rubygems.org with `gem install readline-ext`.
    * We no longer need to install libraries like `libreadline` or `libedit`.

## C API updates

## Implementation improvements

* `defined?(@ivar)` is optimized with Object Shapes.
* Name resolution such as `Socket.getaddrinfo` can now be interrupted. [[Feature #19965]]

### GC

* Major performance improvements over 3.2
    * Young objects referenced by old objects are no longer immediately
      promoted to the old generation. This significantly reduces the frequency of
      major GC collections. [[Feature #19678]]
    * A new `REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO` tuning variable was
      introduced to control the number of unprotected objects cause a major GC
      collection to trigger. The default is set to `0.01` (1%). This significantly
      reduces the frequency of major GC collection. [[Feature #19571]]
    * Write Barriers were implemented for many core types that were missing them,
      notably `Time`, `Enumerator`, `MatchData`, `Method`, `File::Stat`, `BigDecimal`
      and several others. This significantly reduces minor GC collection time and major
      GC collection frequency.
    * Most core classes are now using Variable Width Allocation, notably `Hash`, `Time`,
      `Thread::Backtrace`, `Thread::Backtrace::Location`, `File::Stat`, `Method`.
      This makes these classes faster to allocate and free, use less memory and reduce
      heap fragmentation.

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
* Code GC now disabled by default, with `--yjit-exec-mem-size` treated as a hard limit
    * Can produce better copy-on-write behavior on forking web servers such as `unicorn`
    * Use the `--yjit-code-gc` option to automatically run code GC when YJIT reaches the size limit
* `ratio_in_yjit` stat produced by `--yjit-stats` is now available in release builds,
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

### M:N Thread scheduler

* M:N Thread scheduler is introduced. [[Feature #19842]]
    * Background: Ruby 1.8 and before, M:1 thread scheduler (M Ruby threads
      with 1 native thread. Called as User level threads or Green threads)
      is used. Ruby 1.9 and later, 1:1 thread scheduler (1 Ruby thread with
      1 native thread). M:1 threads takes lower resources compare with 1:1
      threads because it needs only 1 native threads. However it is difficult
      to support context switching for all of blocking operation so 1:1
      threads are employed from Ruby 1.9. M:N thread scheduler uses N native
      threads for M Ruby threads (N is small number in general). It doesn't
      need same number of native threads as Ruby threads (similar to the M:1
      thread scheduler). Also our M:N threads supports blocking operations
      well same as 1:1 threads. See the ticket for more details.
      Our M:N thread scheduler refers on the goroutine scheduler in the
      Go language.
    * In a ractor, only 1 thread can run in a same time because of
      implementation. Therefore, applications that use only one Ractor
      (most applications) M:N thread scheduler works as M:1 thread scheduler
      with further extension from Ruby 1.8.
    * M:N thread scheduler can introduce incompatibility for C-extensions,
      so it is disabled by default on the main Ractors.
      `RUBY_MN_THREADS=1` environment variable will enable it.
      On non-main Ractors, M:N thread scheduler is enabled (and can not
      disable it now).
    * `N` (the number of native threads) can be specified with `RUBY_MAX_CPU`
      environment variable. The default is 8.
      Note that more than `N` native threads are used to support many kind of
      blocking operations.

[Bug #17146]:     https://bugs.ruby-lang.org/issues/17146
[Feature #18183]: https://bugs.ruby-lang.org/issues/18183
[Feature #18498]: https://bugs.ruby-lang.org/issues/18498
[Feature #18515]: https://bugs.ruby-lang.org/issues/18515
[Feature #18551]: https://bugs.ruby-lang.org/issues/18551
[Feature #18885]: https://bugs.ruby-lang.org/issues/18885
[Bug #19012]:     https://bugs.ruby-lang.org/issues/19012
[Bug #19150]:     https://bugs.ruby-lang.org/issues/19150
[Feature #19314]: https://bugs.ruby-lang.org/issues/19314
[Feature #19347]: https://bugs.ruby-lang.org/issues/19347
[Feature #19351]: https://bugs.ruby-lang.org/issues/19351
[Feature #19362]: https://bugs.ruby-lang.org/issues/19362
[Feature #19521]: https://bugs.ruby-lang.org/issues/19521
[Feature #19538]: https://bugs.ruby-lang.org/issues/19538
[Feature #19561]: https://bugs.ruby-lang.org/issues/19561
[Feature #19571]: https://bugs.ruby-lang.org/issues/19571
[Feature #19572]: https://bugs.ruby-lang.org/issues/19572
[Feature #19591]: https://bugs.ruby-lang.org/issues/19591
[Feature #19630]: https://bugs.ruby-lang.org/issues/19630
[Feature #19678]: https://bugs.ruby-lang.org/issues/19678
[Feature #19714]: https://bugs.ruby-lang.org/issues/19714
[Feature #19776]: https://bugs.ruby-lang.org/issues/19776
[Feature #19777]: https://bugs.ruby-lang.org/issues/19777
[Feature #19785]: https://bugs.ruby-lang.org/issues/19785
[Feature #19790]: https://bugs.ruby-lang.org/issues/19790
[Feature #19842]: https://bugs.ruby-lang.org/issues/19842
[Feature #19843]: https://bugs.ruby-lang.org/issues/19843
[Bug #19868]:     https://bugs.ruby-lang.org/issues/19868
[Feature #19965]: https://bugs.ruby-lang.org/issues/19965
