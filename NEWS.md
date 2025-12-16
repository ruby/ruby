# NEWS for Ruby 4.0.0

This document is a list of user-visible feature changes
since the **3.4.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* `*nil` no longer calls `nil.to_a`, similar to how `**nil` does
  not call `nil.to_hash`.  [[Feature #21047]]

* Logical binary operators (`||`, `&&`, `and` and `or`) at the
  beginning of a line continue the previous line, like fluent dot.
  The following two code are equal:

    ```ruby
    if condition1
       && condition2
      ...
    end
    ```

    ```ruby
    if condition1 && condition2
      ...
    end
    ```

    [[Feature #20925]]

## Core classes updates

Note: We're only listing outstanding class updates.

* Enumerator

    * `Enumerator.produce` now accepts an optional `size` keyword argument
      to specify the size of the enumerator.  It can be an integer,
      `Float::INFINITY`, a callable object (such as a lambda), or `nil` to
      indicate unknown size.  When not specified, the size is unknown (`nil`).
      Previously, the size was always `Float::INFINITY` and not specifiable.

        ```ruby
        # Infinite enumerator
        enum = Enumerator.produce(1, size: Float::INFINITY, &:succ)
        enum.size  # => Float::INFINITY

        # Finite enumerator with known/computable size
        abs_dir = File.expand_path("./baz") # => "/foo/bar/baz"
        traverser = Enumerator.produce(abs_dir, size: -> { abs_dir.count("/") + 1 }) {
          raise StopIteration if it == "/"
          File.dirname(it)
        }
        traverser.size  # => 4
        ```

      [[Feature #21701]]

* Kernel

    * `Kernel#inspect` now checks for the existence of a `#instance_variables_to_inspect` method,
      allowing control over which instance variables are displayed in the `#inspect` string:

        ```ruby
        class DatabaseConfig
          def initialize(host, user, password)
            @host = host
            @user = user
            @password = password
          end

          private def instance_variables_to_inspect = [:@host, :@user]
        end

        conf = DatabaseConfig.new("localhost", "root", "hunter2")
        conf.inspect #=> #<DatabaseConfig:0x0000000104def350 @host="localhost", @user="root">
        ```

        [[Feature #21219]]

    * A deprecated behavior, process creation by `Kernel#open` with a
      leading `|`, was removed.  [[Feature #19630]]

* Array

    * `Array#rfind` has been added as a more efficient alternative to `array.reverse_each.find` [[Feature #21678]]
    * `Array#find` has been added as a more efficient override of `Enumerable#find` [[Feature #21678]]

* Binding

    * `Binding#local_variables` does no longer include numbered parameters.
      Also, `Binding#local_variable_get`, `Binding#local_variable_set`, and
      `Binding#local_variable_defined?` reject to handle numbered parameters.
      [[Bug #21049]]

    * `Binding#implicit_parameters`, `Binding#implicit_parameter_get`, and
      `Binding#implicit_parameter_defined?` have been added to access
      numbered parameters and "it" parameter. [[Bug #21049]]

* File

    * `File::Stat#birthtime` is now available on Linux via the statx
      system call when supported by the kernel and filesystem.
      [[Feature #21205]]

* IO

    * `IO.select` accepts `Float::INFINITY` as a timeout argument.
      [[Feature #20610]]

    * A deprecated behavior, process creation by `IO` class methods
      with a leading `|`, was removed.  [[Feature #19630]]

* Math

    * `Math.log1p` and `Math.expm1` are added. [[Feature #21527]]

* Method

    * `Method#source_location`, `Proc#source_location`, and
      `UnboundMethod#source_location` now return extended location
      information with 5 elements: `[path, start_line, start_column,
      end_line, end_column]`. The previous 2-element format `[path,
      line]` can still be obtained by calling `.take(2)` on the result.
      [[Feature #6012]]

* Proc

    * `Proc#parameters` now shows anonymous optional parameters as `[:opt]`
      instead of `[:opt, nil]`, making the output consistent with when the
      anonymous parameter is required. [[Bug #20974]]

* Ractor

    * `Ractor::Port` class was added for a new synchronization mechanism
      to communicate between Ractors. [[Feature #21262]]

        ```ruby
        port1 = Ractor::Port.new
        port2 = Ractor::Port.new
        Ractor.new port1, port2 do |port1, port2|
          port1 << 1
          port2 << 11
          port1 << 2
          port2 << 12
        end
        2.times{ p port1.receive } #=> 1, 2
        2.times{ p port2.receive } #=> 11, 12
        ```

        `Ractor::Port` provides the following methods:

        * `Ractor::Port#receive`
        * `Ractor::Port#send` (or `Ractor::Port#<<`)
        * `Ractor::Port#close`
        * `Ractor::Port#closed?`

        As result, `Ractor.yield` and `Ractor#take` were removed.

    * `Ractor#join` and `Ractor#value` were added to wait for the
      termination of a Ractor. These are similar to `Thread#join`
      and `Thread#value`.

    * `Ractor#monitor` and `Ractor#unmonitor` were added as low-level
      interfaces used internally to implement `Ractor#join`.

    * `Ractor.select` now only accepts Ractors and Ports. If Ractors are given,
      it returns when a Ractor terminates.

    * `Ractor#default_port` was added. Each `Ractor` has a default port,
      which is used by `Ractor.send`, `Ractor.receive`.

    * `Ractor#close_incoming` and `Ractor#close_outgoing` were removed.

    * `Ractor.shareable_proc` and `Ractor.shareable_lambda` is introduced
      to make shareable Proc or lambda.
      [[Feature #21550]], [[Feature #21557]]

* Range

    * `Range#to_set` and `Enumerator#to_set` now perform size checks to prevent
      issues with endless ranges. [[Bug #21654]]

    * `Range#overlap?` now correctly handles infinite (unbounded) ranges.
      [[Bug #21185]]

    * `Range#max` behavior on beginless integer ranges has been fixed.
      [[Bug #21174]] [[Bug #21175]]

* Ruby

    * A new toplevel module `Ruby` has been defined, which contains
      Ruby-related constants. This module was reserved in Ruby 3.4
      and is now officially defined. [[Feature #20884]]

* Ruby::Box

    * A new (experimental) feature to provide separation about definitions.
      For the detail of "Ruby Box", see [doc/language/box.md](doc/language/box.md).
      [[Feature #21311]] [[Misc #21385]]

* Set

    * `Set` is now a core class, instead of an autoloaded stdlib class.
      [[Feature #21216]]

    * `Set#inspect` now uses a simpler displays, similar to literal arrays.
      (e.g., `Set[1, 2, 3]` instead of `#<Set: {1, 2, 3}>`). [[Feature #21389]]

    * Passing arguments to `Set#to_set` and `Enumerable#to_set` is now deprecated.
      [[Feature #21390]]

* Socket

    * `Socket.tcp` & `TCPSocket.new` accepts an `open_timeout` keyword argument to specify
      the timeout for the initial connection. [[Feature #21347]]

* String

    * Update Unicode to Version 17.0.0 and Emoji Version 17.0.
      [[Feature #19908]][[Feature #20724]][[Feature #21275]] (also applies to Regexp)

    * `String#strip`, `strip!`, `lstrip`, `lstrip!`, `rstrip`, and `rstrip!`
       are extended to accept `*selectors` arguments. [[Feature #21552]]

* Thread

    * Introduce support for `Thread#raise(cause:)` argument similar to
      `Kernel#raise`. [[Feature #21360]]

* Fiber

    * Introduce support for `Fiber#raise(cause:)` argument similar to
      `Kernel#raise`. [[Feature #21360]]

* Fiber::Scheduler

    * Introduce `Fiber::Scheduler#fiber_interrupt` to interrupt a fiber with a
      given exception. The initial use case is to interrupt a fiber that is
      waiting on a blocking IO operation when the IO operation is closed.
      [[Feature #21166]]

* Pathname

    * Pathname has been promoted from a default gem to a core class of Ruby.
      [[Feature #17473]]

## Stdlib updates

The following bundled gems are promoted from default gems.

* ostruct 0.6.3
* pstore 0.2.0
* benchmark 0.5.0
* logger 1.7.0
* rdoc 6.17.0
* win32ole 1.9.2
* irb 1.15.3
* reline 0.6.3
* readline 0.0.4
* fiddle 1.1.8

We only list stdlib changes that are notable feature changes.

Other changes are listed in the following sections. We also listed release
history from the previous bundled version that is Ruby 3.3.0 if it has GitHub
releases.

The following default gem is added.

* win32-registry 0.1.2

The following default gems are updated.

* RubyGems 4.0.1
* bundler 4.0.1
* date 3.5.1
* digest 3.2.1
* english 0.8.1
* erb 6.0.1
* etc 1.4.6
* fcntl 1.3.0
* fileutils 1.8.0
* forwardable 1.4.0
* io-console 0.8.2
* io-nonblock 0.3.2
* io-wait 0.4.0.dev
* ipaddr 1.2.8
* json 2.18.0
* net-http 0.8.0
* openssl 4.0.0
* optparse 0.8.1
* pp 0.6.3
* prism 1.6.0
* psych 5.3.0
* resolv 0.7.0
* stringio 3.1.9.dev
* strscan 3.1.6.dev
* timeout 0.5.0
* uri 1.1.1
* weakref 0.1.4
* zlib 3.2.2

The following bundled gems are added.


The following bundled gems are updated.

* minitest 5.27.0
* power_assert 3.0.1
* rake 13.3.1
* test-unit 3.7.3
* rexml 3.4.4
* net-ftp 0.3.9
* net-imap 0.5.12
* net-smtp 0.5.1
* matrix 0.4.3
* prime 0.1.4
* rbs 3.9.5
* typeprof 0.31.0
* debug 1.11.0
* base64 0.3.0
* bigdecimal 3.3.1
* drb 2.2.3
* syslog 0.3.0
* csv 3.3.5
* repl_type_completor 0.1.12

## Supported platforms

* Windows

    * Dropped support for MSVC versions older than 14.0 (_MSC_VER 1900).
      This means Visual Studio 2015 or later is now required.

## Compatibility issues

* The following methods were removed from Ractor due to the addition of `Ractor::Port`:

    * `Ractor.yield`
    * `Ractor#take`
    * `Ractor#close_incoming`
    * `Ractor#close_outgoging`

    [[Feature #21262]]

* `ObjectSpace._id2ref` is deprecated. [[Feature #15408]]

* `Process::Status#&` and `Process::Status#>>` have been removed.
  They were deprecated in Ruby 3.3. [[Bug #19868]]

* `rb_path_check` has been removed. This function was used for
  `$SAFE` path checking which was removed in Ruby 2.7,
  and was already deprecated,.
  [[Feature #20971]]

## Stdlib compatibility issues

* CGI library is removed from the default gems. Now we only provide `cgi/escape` for
  the following methods:

    * `CGI.escape` and `CGI.unescape`
    * `CGI.escapeHTML` and `CGI.unescapeHTML`
    * `CGI.escapeURIComponent` and `CGI.unescapeURIComponent`
    * `CGI.escapeElement` and `CGI.unescapeElement`

    [[Feature #21258]]

* With the move of `Set` from stdlib to core class, `set/sorted_set.rb` has
  been removed, and `SortedSet` is no longer an autoloaded constant. Please
  install the `sorted_set` gem and `require 'sorted_set'` to use `SortedSet`.
  [[Feature #21287]]

## C API updates

* IO

    * `rb_thread_fd_close` is deprecated and now a no-op. If you need to expose
      file descriptors from C extensions to Ruby code, create an `IO` instance
      using `RUBY_IO_MODE_EXTERNAL` and use `rb_io_close(io)` to close it (this
      also interrupts and waits for all pending operations on the `IO`
      instance). Directly closing file descriptors does not interrupt pending
      operations, and may lead to undefined behaviour. In other words, if two
      `IO` objects share the same file descriptor, closing one does not affect
      the other. [[Feature #18455]]

* GVL

    * `rb_thread_call_with_gvl` now works with or without the GVL.
      This allows gems to avoid checking `ruby_thread_has_gvl_p`.
      Please still be diligent about the GVL. [[Feature #20750]]

* Set

    * A C API for `Set` has been added. The following methods are supported:
      [[Feature #21459]]

        * `rb_set_foreach`
        * `rb_set_new`
        * `rb_set_new_capa`
        * `rb_set_lookup`
        * `rb_set_add`
        * `rb_set_clear`
        * `rb_set_delete`
        * `rb_set_size`

## Implementation improvements

### Ractor

A lot of work has gone into making Ractors more stable, performant, and usable. These improvements bring Ractors implementation closer to leaving experimental status.

* Performance improvements
    * Frozen strings and the symbol table internally use a lock-free hash set
    * Method cache lookups avoid locking in most cases
    * Class (and geniv) instance variable access is faster and avoids locking
    * Cache contention is avoided during object allocation
    * `object_id` avoids locking in most cases
* Bug fixes and stability
    * Fixed possible deadlocks when combining Ractors and Threads
    * Fixed issues with require and autoload in a Ractor
    * Fixed encoding/transcoding issues across Ractors
    * Fixed race conditions in GC operations and method invalidation
    * Fixed issues with processes forking after starting a Ractor

## JIT

* ZJIT
    * Introduce an [experimental method-based JIT compiler](https://docs.ruby-lang.org/en/master/jit/zjit_md.html).
      To enable `--zjit` support, build Ruby with Rust 1.85.0 or later.
    * As of Ruby 4.0.0, ZJIT is faster than the interpreter, but not yet as fast as YJIT.
      We encourage experimentation with ZJIT, but advise against deploying it in production for now.
    * Our goal is to make ZJIT faster than YJIT and production-ready in Ruby 4.1.
* YJIT
    * `RubyVM::YJIT.runtime_stats`
        * `ratio_in_yjit` no longer works in the default build.
          Use `--enable-yjit=stats` on `configure` to enable it on `--yjit-stats`.
        * Add `invalidate_everything` to default stats, which is
          incremented when every code is invalidated by TracePoint.
    * Add `mem_size:` and `call_threshold:` options to `RubyVM::YJIT.enable`.
* RJIT
    * `--rjit` is removed. We will move the implementation of the third-party JIT API
      to the [ruby/rjit](https://github.com/ruby/rjit) repository.

[Feature #6012]: https://bugs.ruby-lang.org/issues/6012
[Feature #15408]: https://bugs.ruby-lang.org/issues/15408
[Feature #17473]: https://bugs.ruby-lang.org/issues/17473
[Feature #18455]: https://bugs.ruby-lang.org/issues/18455
[Feature #19630]: https://bugs.ruby-lang.org/issues/19630
[Bug #19868]:     https://bugs.ruby-lang.org/issues/19868
[Feature #19908]: https://bugs.ruby-lang.org/issues/19908
[Feature #20610]: https://bugs.ruby-lang.org/issues/20610
[Feature #20724]: https://bugs.ruby-lang.org/issues/20724
[Feature #20750]: https://bugs.ruby-lang.org/issues/20750
[Feature #20884]: https://bugs.ruby-lang.org/issues/20884
[Feature #20925]: https://bugs.ruby-lang.org/issues/20925
[Feature #20971]: https://bugs.ruby-lang.org/issues/20971
[Bug #20974]:     https://bugs.ruby-lang.org/issues/20974
[Feature #21047]: https://bugs.ruby-lang.org/issues/21047
[Bug #21049]:     https://bugs.ruby-lang.org/issues/21049
[Feature #21166]: https://bugs.ruby-lang.org/issues/21166
[Bug #21174]:     https://bugs.ruby-lang.org/issues/21174
[Bug #21175]:     https://bugs.ruby-lang.org/issues/21175
[Bug #21185]:     https://bugs.ruby-lang.org/issues/21185
[Feature #21205]: https://bugs.ruby-lang.org/issues/21205
[Feature #21216]: https://bugs.ruby-lang.org/issues/21216
[Feature #21219]: https://bugs.ruby-lang.org/issues/21219
[Feature #21258]: https://bugs.ruby-lang.org/issues/21258
[Feature #21262]: https://bugs.ruby-lang.org/issues/21262
[Feature #21275]: https://bugs.ruby-lang.org/issues/21275
[Feature #21287]: https://bugs.ruby-lang.org/issues/21287
[Feature #21311]: https://bugs.ruby-lang.org/issues/21311
[Feature #21347]: https://bugs.ruby-lang.org/issues/21347
[Feature #21360]: https://bugs.ruby-lang.org/issues/21360
[Misc #21385]:    https://bugs.ruby-lang.org/issues/21385
[Feature #21389]: https://bugs.ruby-lang.org/issues/21389
[Feature #21390]: https://bugs.ruby-lang.org/issues/21390
[Feature #21459]: https://bugs.ruby-lang.org/issues/21459
[Feature #21527]: https://bugs.ruby-lang.org/issues/21527
[Feature #21550]: https://bugs.ruby-lang.org/issues/21550
[Feature #21557]: https://bugs.ruby-lang.org/issues/21557
[Bug #21654]:     https://bugs.ruby-lang.org/issues/21654
[Feature #21678]: https://bugs.ruby-lang.org/issues/21678
[Feature #21701]: https://bugs.ruby-lang.org/issues/21701
