# NEWS for Ruby 4.0.0

This document is a list of user-visible feature changes
since the **3.4.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* `*nil` no longer calls `nil.to_a`, similar to how `**nil` does
  not call `nil.to_hash`.  [[Feature #21047]]

* Logical binary operators (`||`, `&&`, `and` and `or`) at the
  beginning of a line continue the previous line, like fluent dot.
  The following code examples are equal:

    ```ruby
    if condition1
       && condition2
      ...
    end
    ```

    Previously:

    ```ruby
    if condition1 && condition2
      ...
    end
    ```

    ```ruby
    if condition1 &&
       condition2
      ...
    end
    ```

    [[Feature #20925]]

## Core classes updates

Note: We're only listing outstanding class updates.

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

* Enumerator

    * `Enumerator.produce` now accepts an optional `size` keyword argument
      to specify the size of the enumerator.  It can be an integer,
      `Float::INFINITY`, a callable object (such as a lambda), or `nil` to
      indicate unknown size.  When not specified, the size defaults to
      `Float::INFINITY`.

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

* ErrorHighlight

    * When an ArgumentError is raised, it now displays code snippets for
      both the method call (caller) and the method definition (callee).
      [[Feature #21543]]

      ```
      test.rb:1:in 'Object#add': wrong number of arguments (given 1, expected 2) (ArgumentError)

          caller: test.rb:3
          | add(1)
            ^^^
          callee: test.rb:1
          | def add(x, y) = x + y
                ^^^
              from test.rb:3:in '<main>'
      ```

* Fiber

    * Introduce support for `Fiber#raise(cause:)` argument similar to
      `Kernel#raise`. [[Feature #21360]]

* Fiber::Scheduler

    * Introduce `Fiber::Scheduler#fiber_interrupt` to interrupt a fiber with a
      given exception. The initial use case is to interrupt a fiber that is
      waiting on a blocking IO operation when the IO operation is closed.
      [[Feature #21166]]

    * Introduce `Fiber::Scheduler#yield` to allow the fiber scheduler to
      continue processing when signal exceptions are disabled.
      [[Bug #21633]]

    * Reintroduce the `Fiber::Scheduler#io_close` hook for asynchronous `IO#close`.

    * Invoke `Fiber::Scheduler#io_write` when flushing the IO write buffer.
      [[Bug #21789]]

* File

    * `File::Stat#birthtime` is now available on Linux via the statx
      system call when supported by the kernel and filesystem.
      [[Feature #21205]]

* IO

    * `IO.select` accepts `Float::INFINITY` as a timeout argument.
      [[Feature #20610]]

    * A deprecated behavior, process creation by `IO` class methods
      with a leading `|`, was removed.  [[Feature #19630]]

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

* Math

    * `Math.log1p` and `Math.expm1` are added. [[Feature #21527]]

* Pathname

    * Pathname has been promoted from a default gem to a core class of Ruby.
      [[Feature #17473]]

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

        As a result, `Ractor.yield` and `Ractor#take` were removed.

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

    * `Ractor.shareable_proc` and `Ractor.shareable_lambda` are introduced
      to make shareable Proc or lambda.
      [[Feature #21550]], [[Feature #21557]]

* Range

    * `Range#to_set` now performs size checks to prevent issues with
      endless ranges. [[Bug #21654]]

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

    * `Set#inspect` now uses a simpler display, similar to literal arrays.
      (e.g., `Set[1, 2, 3]` instead of `#<Set: {1, 2, 3}>`). [[Feature #21389]]

    * Passing arguments to `Set#to_set` and `Enumerable#to_set` is now deprecated.
      [[Feature #21390]]

* Socket

    * `Socket.tcp` & `TCPSocket.new` accepts an `open_timeout` keyword argument to specify
      the timeout for the initial connection. [[Feature #21347]]
    * When a user-specified timeout occurred in `TCPSocket.new`, either `Errno::ETIMEDOUT`
      or `IO::TimeoutError` could previously be raised depending on the situation.
      This behavior has been unified so that `IO::TimeoutError` is now consistently raised.
      (Please note that, in `Socket.tcp`, there are still cases where `Errno::ETIMEDOUT`
      may be raised in similar situations, and that in both cases `Errno::ETIMEDOUT` may be
      raised when the timeout occurs at the OS level.)

* String

    * Update Unicode to Version 17.0.0 and Emoji Version 17.0.
      [[Feature #19908]][[Feature #20724]][[Feature #21275]] (also applies to Regexp)

    * `String#strip`, `strip!`, `lstrip`, `lstrip!`, `rstrip`, and `rstrip!`
       are extended to accept `*selectors` arguments. [[Feature #21552]]

* Thread

    * Introduce support for `Thread#raise(cause:)` argument similar to
      `Kernel#raise`. [[Feature #21360]]

## Stdlib updates

We only list stdlib changes that are notable feature changes.

Other changes are listed in the following sections. We also listed release
history from the previous bundled version that is Ruby 3.4.0 if it has GitHub
releases.

The following bundled gems are promoted from default gems.

* ostruct 0.6.3
  * 0.6.1 to [v0.6.2][ostruct-v0.6.2], [v0.6.3][ostruct-v0.6.3]
* pstore 0.2.0
  * 0.1.4 to [v0.2.0][pstore-v0.2.0]
* benchmark 0.5.0
  * 0.4.0 to [v0.4.1][benchmark-v0.4.1], [v0.5.0][benchmark-v0.5.0]
* logger 1.7.0
  * 1.6.4 to [v1.6.5][logger-v1.6.5], [v1.6.6][logger-v1.6.6], [v1.7.0][logger-v1.7.0]
* rdoc 7.0.3
  * 6.14.0 to [v6.14.1][rdoc-v6.14.1], [v6.14.2][rdoc-v6.14.2], [v6.15.0][rdoc-v6.15.0], [v6.15.1][rdoc-v6.15.1], [v6.16.0][rdoc-v6.16.0], [v6.16.1][rdoc-v6.16.1], [v6.17.0][rdoc-v6.17.0], [v7.0.0][rdoc-v7.0.0], [v7.0.1][rdoc-v7.0.1], [v7.0.2][rdoc-v7.0.2], [v7.0.3][rdoc-v7.0.3]
* win32ole 1.9.2
  * 1.9.1 to [v1.9.2][win32ole-v1.9.2]
* irb 1.16.0
  * 1.14.3 to [v1.15.0][irb-v1.15.0], [v1.15.1][irb-v1.15.1], [v1.15.2][irb-v1.15.2], [v1.15.3][irb-v1.15.3], [v1.16.0][irb-v1.16.0]
* reline 0.6.3
  * 0.6.0 to [v0.6.1][reline-v0.6.1], [v0.6.2][reline-v0.6.2], [v0.6.3][reline-v0.6.3]
* readline 0.0.4
* fiddle 1.1.8
  * 1.1.6 to [v1.1.7][fiddle-v1.1.7], [v1.1.8][fiddle-v1.1.8]

The following default gem is added.

* win32-registry 0.1.2

The following default gems are updated.

* RubyGems 4.0.3
* bundler 4.0.3
* date 3.5.1
  * 3.4.1 to [v3.5.0][date-v3.5.0], [v3.5.1][date-v3.5.1]
* delegate 0.6.1
  * 0.4.0 to [v0.5.0][delegate-v0.5.0], [v0.6.0][delegate-v0.6.0], [v0.6.1][delegate-v0.6.1]
* digest 3.2.1
  * 3.2.0 to [v3.2.1][digest-v3.2.1]
* english 0.8.1
  * 0.8.0 to [v0.8.1][english-v0.8.1]
* erb 6.0.1
  * 4.0.4 to [v5.1.2][erb-v5.1.2], [v5.1.3][erb-v5.1.3], [v6.0.0][erb-v6.0.0], [v6.0.1][erb-v6.0.1]
* error_highlight 0.7.1
* etc 1.4.6
* fcntl 1.3.0
  * 1.2.0 to [v1.3.0][fcntl-v1.3.0]
* fileutils 1.8.0
  * 1.7.3 to [v1.8.0][fileutils-v1.8.0]
* forwardable 1.4.0
  * 1.3.3 to [v1.4.0][forwardable-v1.4.0]
* io-console 0.8.2
  * 0.8.1 to [v0.8.2][io-console-v0.8.2]
* io-nonblock 0.3.2
* io-wait 0.4.0
  * 0.3.2 to [v0.3.3][io-wait-v0.3.3], [v0.3.5.test1][io-wait-v0.3.5.test1], [v0.3.5][io-wait-v0.3.5], [v0.3.6][io-wait-v0.3.6], [v0.4.0][io-wait-v0.4.0]
* ipaddr 1.2.8
* json 2.18.0
  * 2.9.1 to [v2.10.0][json-v2.10.0], [v2.10.1][json-v2.10.1], [v2.10.2][json-v2.10.2], [v2.11.0][json-v2.11.0], [v2.11.1][json-v2.11.1], [v2.11.2][json-v2.11.2], [v2.11.3][json-v2.11.3], [v2.12.0][json-v2.12.0], [v2.12.1][json-v2.12.1], [v2.12.2][json-v2.12.2], [v2.13.0][json-v2.13.0], [v2.13.1][json-v2.13.1], [v2.13.2][json-v2.13.2], [v2.14.0][json-v2.14.0], [v2.14.1][json-v2.14.1], [v2.15.0][json-v2.15.0], [v2.15.1][json-v2.15.1], [v2.15.2][json-v2.15.2], [v2.16.0][json-v2.16.0], [v2.17.0][json-v2.17.0], [v2.17.1][json-v2.17.1], [v2.18.0][json-v2.18.0]
* net-http 0.9.1
  * 0.6.0 to [v0.7.0][net-http-v0.7.0], [v0.8.0][net-http-v0.8.0], [v0.9.0][net-http-v0.9.0], [v0.9.1][net-http-v0.9.1]
* openssl 4.0.0
  * 3.3.1 to [v3.3.2][openssl-v3.3.2], [v4.0.0][openssl-v4.0.0]
* optparse 0.8.1
  * 0.6.0 to [v0.7.0][optparse-v0.7.0], [v0.8.0][optparse-v0.8.0], [v0.8.1][optparse-v0.8.1]
* pp 0.6.3
  * 0.6.2 to [v0.6.3][pp-v0.6.3]
* prism 1.7.0
  * 1.5.2 to [v1.6.0][prism-v1.6.0], [v1.7.0][prism-v1.7.0]
* psych 5.3.1
  * 5.2.2 to [v5.2.3][psych-v5.2.3], [v5.2.4][psych-v5.2.4], [v5.2.5][psych-v5.2.5], [v5.2.6][psych-v5.2.6], [v5.3.0][psych-v5.3.0], [v5.3.1][psych-v5.3.1]
* resolv 0.7.0
  * 0.6.2 to [v0.6.3][resolv-v0.6.3], [v0.7.0][resolv-v0.7.0]
* stringio 3.2.0
  * 3.1.2 to [v3.1.3][stringio-v3.1.3], [v3.1.4][stringio-v3.1.4], [v3.1.5][stringio-v3.1.5], [v3.1.6][stringio-v3.1.6], [v3.1.7][stringio-v3.1.7], [v3.1.8][stringio-v3.1.8], [v3.1.9][stringio-v3.1.9], [v3.2.0][stringio-v3.2.0]
* strscan 3.1.6
  * 3.1.2 to [v3.1.3][strscan-v3.1.3], [v3.1.4][strscan-v3.1.4], [v3.1.5][strscan-v3.1.5], [v3.1.6][strscan-v3.1.6]
* time 0.4.2
  * 0.4.1 to [v0.4.2][time-v0.4.2]
* timeout 0.6.0
  * 0.4.3 to [v0.4.4][timeout-v0.4.4], [v0.5.0][timeout-v0.5.0], [v0.6.0][timeout-v0.6.0]
* uri 1.1.1
  * 1.0.4 to [v1.1.0][uri-v1.1.0], [v1.1.1][uri-v1.1.1]
* weakref 0.1.4
  * 0.1.3 to [v0.1.4][weakref-v0.1.4]
* zlib 3.2.2
  * 3.2.1 to [v3.2.2][zlib-v3.2.2]

The following bundled gems are updated.

* minitest 6.0.0
* power_assert 3.0.1
  * 2.0.5 to [v3.0.0][power_assert-v3.0.0], [v3.0.1][power_assert-v3.0.1]
* rake 13.3.1
  * 13.2.1 to [v13.3.0][rake-v13.3.0], [v13.3.1][rake-v13.3.1]
* test-unit 3.7.5
  * 3.6.7 to [3.6.8][test-unit-3.6.8], [3.6.9][test-unit-3.6.9], [3.7.0][test-unit-3.7.0], [3.7.1][test-unit-3.7.1], [3.7.2][test-unit-3.7.2], [3.7.3][test-unit-3.7.3], [3.7.4][test-unit-3.7.4], [3.7.5][test-unit-3.7.5]
* rexml 3.4.4
* rss 0.3.2
  * 0.3.1 to [0.3.2][rss-0.3.2]
* net-ftp 0.3.9
  * 0.3.8 to [v0.3.9][net-ftp-v0.3.9]
* net-imap 0.6.2
  * 0.5.8 to [v0.5.9][net-imap-v0.5.9], [v0.5.10][net-imap-v0.5.10], [v0.5.11][net-imap-v0.5.11], [v0.5.12][net-imap-v0.5.12], [v0.5.13][net-imap-v0.5.13], [v0.6.0][net-imap-v0.6.0], [v0.6.1][net-imap-v0.6.1], [v0.6.2][net-imap-v0.6.2]
* net-smtp 0.5.1
  * 0.5.0 to [v0.5.1][net-smtp-v0.5.1]
* matrix 0.4.3
  * 0.4.2 to [v0.4.3][matrix-v0.4.3]
* prime 0.1.4
  * 0.1.3 to [v0.1.4][prime-v0.1.4]
* rbs 3.10.0
  * 3.8.0 to [v3.8.1][rbs-v3.8.1], [v3.9.0.dev.1][rbs-v3.9.0.dev.1], [v3.9.0.pre.1][rbs-v3.9.0.pre.1], [v3.9.0.pre.2][rbs-v3.9.0.pre.2], [v3.9.0][rbs-v3.9.0], [v3.9.1][rbs-v3.9.1], [v3.9.2][rbs-v3.9.2], [v3.9.3][rbs-v3.9.3], [v3.9.4][rbs-v3.9.4], [v3.9.5][rbs-v3.9.5], [v3.10.0.pre.1][rbs-v3.10.0.pre.1], [v3.10.0.pre.2][rbs-v3.10.0.pre.2], [v3.10.0][rbs-v3.10.0]
* typeprof 0.31.1
* debug 1.11.1
  * 1.11.0 to [v1.11.1][debug-v1.11.1]
* base64 0.3.0
  * 0.2.0 to [v0.3.0][base64-v0.3.0]
* bigdecimal 4.0.1
  * 3.1.8 to [v3.2.0][bigdecimal-v3.2.0], [v3.2.1][bigdecimal-v3.2.1], [v3.2.2][bigdecimal-v3.2.2], [v3.2.3][bigdecimal-v3.2.3], [v3.3.0][bigdecimal-v3.3.0], [v3.3.1][bigdecimal-v3.3.1], [v4.0.0][bigdecimal-v4.0.0], [v4.0.1][bigdecimal-v4.0.1]
* drb 2.2.3
  * 2.2.1 to [v2.2.3][drb-v2.2.3]
* syslog 0.3.0
  * 0.2.0 to [v0.3.0][syslog-v0.3.0]
* csv 3.3.5
  * 3.3.2 to [v3.3.3][csv-v3.3.3], [v3.3.4][csv-v3.3.4], [v3.3.5][csv-v3.3.5]
* repl_type_completor 0.1.12

### RubyGems and Bundler

Ruby 4.0 bundled RubyGems and Bundler version 4. see the following links for details.

* [Upgrading to RubyGems/Bundler 4 - RubyGems Blog](https://blog.rubygems.org/2025/12/03/upgrade-to-rubygems-bundler-4.html)
* [4.0.0 Released - RubyGems Blog](https://blog.rubygems.org/2025/12/03/4.0.0-released.html)
* [4.0.1 Released - RubyGems Blog](https://blog.rubygems.org/2025/12/09/4.0.1-released.html)
* [4.0.2 Released - RubyGems Blog](https://blog.rubygems.org/2025/12/17/4.0.2-released.html)
* [4.0.3 Released - RubyGems Blog](https://blog.rubygems.org/2025/12/23/4.0.3-released.html)

## Supported platforms

* Windows

    * Dropped support for MSVC versions older than 14.0 (_MSC_VER 1900).
      This means Visual Studio 2015 or later is now required.

## Compatibility issues

* The following methods were removed from Ractor due to the addition of `Ractor::Port`:

    * `Ractor.yield`
    * `Ractor#take`
    * `Ractor#close_incoming`
    * `Ractor#close_outgoing`

    [[Feature #21262]]

* `ObjectSpace._id2ref` is deprecated. [[Feature #15408]]

* `Process::Status#&` and `Process::Status#>>` have been removed.
  They were deprecated in Ruby 3.3. [[Bug #19868]]

* `rb_path_check` has been removed. This function was used for
  `$SAFE` path checking which was removed in Ruby 2.7,
  and was already deprecated.
  [[Feature #20971]]

* A backtrace for `ArgumentError` of "wrong number of arguments" now
  include the receiver's class or module name (e.g., in `Foo#bar`
  instead of in `bar`). [[Bug #21698]]

* Backtraces no longer display `internal` frames.
  These methods now appear as if it is in the Ruby source file,
  consistent with other C-implemented methods. [[Bug #20968]]

  Before:
  ```
  ruby -e '[1].fetch_values(42)'
  <internal:array>:211:in 'Array#fetch': index 42 outside of array bounds: -1...1 (IndexError)
          from <internal:array>:211:in 'block in Array#fetch_values'
          from <internal:array>:211:in 'Array#map!'
          from <internal:array>:211:in 'Array#fetch_values'
          from -e:1:in '<main>'
  ```

  After:
  ```
  $ ruby -e '[1].fetch_values(42)'
  -e:1:in 'Array#fetch_values': index 42 outside of array bounds: -1...1 (IndexError)
          from -e:1:in '<main>'
  ```

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

* Net::HTTP

    * The default behavior of automatically setting the `Content-Type` header
      to `application/x-www-form-urlencoded` for requests with a body
      (e.g., `POST`, `PUT`) when the header was not explicitly set has been
      removed. If your application relied on this automatic default, your
      requests will now be sent without a Content-Type header, potentially
      breaking compatibility with certain servers.
      [[GH-net-http #205]]

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

* `Class#new` (ex. `Object.new`) is faster in all cases, but especially when passing keyword arguments. This has also been integrated into YJIT and ZJIT. [[Feature #21254]]
* GC heaps of different size pools now grow independently, reducing memory usage when only some pools contain long-lived objects
* GC sweeping is faster on pages of large objects
* "Generic ivar" objects (String, Array, `TypedData`, etc.) now use a new internal "fields" object for faster instance variable access
* The GC avoids maintaining an internal `id2ref` table until it is first used, making `object_id` allocation and GC sweeping faster
* `object_id` and `hash` are faster on Class and Module objects
* Larger bignum Integers can remain embedded using variable width allocation
* `Random`, `Enumerator::Product`, `Enumerator::Chain`, `Addrinfo`,
  `StringScanner`, and some internal objects are now write-barrier protected,
  which reduces GC overhead.

### Ractor

A lot of work has gone into making Ractors more stable, performant, and usable. These improvements bring Ractor implementation closer to leaving experimental status.

* Performance improvements
    * Frozen strings and the symbol table internally use a lock-free hash set [[Feature #21268]]
    * Method cache lookups avoid locking in most cases
    * Class (and generic ivar) instance variable access is faster and avoids locking
    * CPU cache contention is avoided in object allocation by using a per-ractor counter
    * CPU cache contention is avoided in xmalloc/xfree by using a thread-local counter
    * `object_id` avoids locking in most cases
* Bug fixes and stability
    * Fixed possible deadlocks when combining Ractors and Threads
    * Fixed issues with require and autoload in a Ractor
    * Fixed encoding/transcoding issues across Ractors
    * Fixed race conditions in GC operations and method invalidation
    * Fixed issues with processes forking after starting a Ractor
    * GC allocation counts are now accurate under Ractors
    * Fixed TracePoints not working after GC [[Bug #19112]]

## JIT

* ZJIT
    * Introduce an [experimental method-based JIT compiler](https://docs.ruby-lang.org/en/master/jit/zjit_md.html).
      Where available, ZJIT can be enabled at runtime with the `--zjit` option or by calling `RubyVM::ZJIT.enable`.
      When building Ruby, Rust 1.85.0 or later is required to include ZJIT support.
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

[Feature #15408]: https://bugs.ruby-lang.org/issues/15408
[Feature #17473]: https://bugs.ruby-lang.org/issues/17473
[Feature #18455]: https://bugs.ruby-lang.org/issues/18455
[Bug #19112]:     https://bugs.ruby-lang.org/issues/19112
[Feature #19630]: https://bugs.ruby-lang.org/issues/19630
[Bug #19868]:     https://bugs.ruby-lang.org/issues/19868
[Feature #19908]: https://bugs.ruby-lang.org/issues/19908
[Feature #20610]: https://bugs.ruby-lang.org/issues/20610
[Feature #20724]: https://bugs.ruby-lang.org/issues/20724
[Feature #20750]: https://bugs.ruby-lang.org/issues/20750
[Feature #20884]: https://bugs.ruby-lang.org/issues/20884
[Feature #20925]: https://bugs.ruby-lang.org/issues/20925
[Bug #20968]:     https://bugs.ruby-lang.org/issues/20968
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
[Feature #21254]: https://bugs.ruby-lang.org/issues/21254
[Feature #21258]: https://bugs.ruby-lang.org/issues/21258
[Feature #21268]: https://bugs.ruby-lang.org/issues/21268
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
[Feature #21543]: https://bugs.ruby-lang.org/issues/21543
[Feature #21550]: https://bugs.ruby-lang.org/issues/21550
[Feature #21552]: https://bugs.ruby-lang.org/issues/21552
[Feature #21557]: https://bugs.ruby-lang.org/issues/21557
[Bug #21633]:     https://bugs.ruby-lang.org/issues/21633
[Bug #21654]:     https://bugs.ruby-lang.org/issues/21654
[Feature #21678]: https://bugs.ruby-lang.org/issues/21678
[Bug #21698]:     https://bugs.ruby-lang.org/issues/21698
[Feature #21701]: https://bugs.ruby-lang.org/issues/21701
[Bug #21789]:     https://bugs.ruby-lang.org/issues/21789
[GH-net-http #205]: https://github.com/ruby/net-http/issues/205
[ostruct-v0.6.2]: https://github.com/ruby/ostruct/releases/tag/v0.6.2
[ostruct-v0.6.3]: https://github.com/ruby/ostruct/releases/tag/v0.6.3
[pstore-v0.2.0]: https://github.com/ruby/pstore/releases/tag/v0.2.0
[benchmark-v0.4.1]: https://github.com/ruby/benchmark/releases/tag/v0.4.1
[benchmark-v0.5.0]: https://github.com/ruby/benchmark/releases/tag/v0.5.0
[logger-v1.6.5]: https://github.com/ruby/logger/releases/tag/v1.6.5
[logger-v1.6.6]: https://github.com/ruby/logger/releases/tag/v1.6.6
[logger-v1.7.0]: https://github.com/ruby/logger/releases/tag/v1.7.0
[rdoc-v6.14.1]: https://github.com/ruby/rdoc/releases/tag/v6.14.1
[rdoc-v6.14.2]: https://github.com/ruby/rdoc/releases/tag/v6.14.2
[rdoc-v6.15.0]: https://github.com/ruby/rdoc/releases/tag/v6.15.0
[rdoc-v6.15.1]: https://github.com/ruby/rdoc/releases/tag/v6.15.1
[rdoc-v6.16.0]: https://github.com/ruby/rdoc/releases/tag/v6.16.0
[rdoc-v6.16.1]: https://github.com/ruby/rdoc/releases/tag/v6.16.1
[rdoc-v6.17.0]: https://github.com/ruby/rdoc/releases/tag/v6.17.0
[rdoc-v7.0.0]: https://github.com/ruby/rdoc/releases/tag/v7.0.0
[rdoc-v7.0.1]: https://github.com/ruby/rdoc/releases/tag/v7.0.1
[rdoc-v7.0.2]: https://github.com/ruby/rdoc/releases/tag/v7.0.2
[rdoc-v7.0.3]: https://github.com/ruby/rdoc/releases/tag/v7.0.3
[win32ole-v1.9.2]: https://github.com/ruby/win32ole/releases/tag/v1.9.2
[irb-v1.15.0]: https://github.com/ruby/irb/releases/tag/v1.15.0
[irb-v1.15.1]: https://github.com/ruby/irb/releases/tag/v1.15.1
[irb-v1.15.2]: https://github.com/ruby/irb/releases/tag/v1.15.2
[irb-v1.15.3]: https://github.com/ruby/irb/releases/tag/v1.15.3
[irb-v1.16.0]: https://github.com/ruby/irb/releases/tag/v1.16.0
[reline-v0.6.1]: https://github.com/ruby/reline/releases/tag/v0.6.1
[reline-v0.6.2]: https://github.com/ruby/reline/releases/tag/v0.6.2
[reline-v0.6.3]: https://github.com/ruby/reline/releases/tag/v0.6.3
[fiddle-v1.1.7]: https://github.com/ruby/fiddle/releases/tag/v1.1.7
[fiddle-v1.1.8]: https://github.com/ruby/fiddle/releases/tag/v1.1.8
[date-v3.5.0]: https://github.com/ruby/date/releases/tag/v3.5.0
[date-v3.5.1]: https://github.com/ruby/date/releases/tag/v3.5.1
[delegate-v0.5.0]: https://github.com/ruby/delegate/releases/tag/v0.5.0
[delegate-v0.6.0]: https://github.com/ruby/delegate/releases/tag/v0.6.0
[delegate-v0.6.1]: https://github.com/ruby/delegate/releases/tag/v0.6.1
[digest-v3.2.1]: https://github.com/ruby/digest/releases/tag/v3.2.1
[english-v0.8.1]: https://github.com/ruby/english/releases/tag/v0.8.1
[erb-v5.1.2]: https://github.com/ruby/erb/releases/tag/v5.1.2
[erb-v5.1.3]: https://github.com/ruby/erb/releases/tag/v5.1.3
[erb-v6.0.0]: https://github.com/ruby/erb/releases/tag/v6.0.0
[erb-v6.0.1]: https://github.com/ruby/erb/releases/tag/v6.0.1
[fcntl-v1.3.0]: https://github.com/ruby/fcntl/releases/tag/v1.3.0
[fileutils-v1.8.0]: https://github.com/ruby/fileutils/releases/tag/v1.8.0
[forwardable-v1.4.0]: https://github.com/ruby/forwardable/releases/tag/v1.4.0
[io-console-v0.8.2]: https://github.com/ruby/io-console/releases/tag/v0.8.2
[io-wait-v0.3.3]: https://github.com/ruby/io-wait/releases/tag/v0.3.3
[io-wait-v0.3.5.test1]: https://github.com/ruby/io-wait/releases/tag/v0.3.5.test1
[io-wait-v0.3.5]: https://github.com/ruby/io-wait/releases/tag/v0.3.5
[io-wait-v0.3.6]: https://github.com/ruby/io-wait/releases/tag/v0.3.6
[io-wait-v0.4.0]: https://github.com/ruby/io-wait/releases/tag/v0.4.0
[json-v2.10.0]: https://github.com/ruby/json/releases/tag/v2.10.0
[json-v2.10.1]: https://github.com/ruby/json/releases/tag/v2.10.1
[json-v2.10.2]: https://github.com/ruby/json/releases/tag/v2.10.2
[json-v2.11.0]: https://github.com/ruby/json/releases/tag/v2.11.0
[json-v2.11.1]: https://github.com/ruby/json/releases/tag/v2.11.1
[json-v2.11.2]: https://github.com/ruby/json/releases/tag/v2.11.2
[json-v2.11.3]: https://github.com/ruby/json/releases/tag/v2.11.3
[json-v2.12.0]: https://github.com/ruby/json/releases/tag/v2.12.0
[json-v2.12.1]: https://github.com/ruby/json/releases/tag/v2.12.1
[json-v2.12.2]: https://github.com/ruby/json/releases/tag/v2.12.2
[json-v2.13.0]: https://github.com/ruby/json/releases/tag/v2.13.0
[json-v2.13.1]: https://github.com/ruby/json/releases/tag/v2.13.1
[json-v2.13.2]: https://github.com/ruby/json/releases/tag/v2.13.2
[json-v2.14.0]: https://github.com/ruby/json/releases/tag/v2.14.0
[json-v2.14.1]: https://github.com/ruby/json/releases/tag/v2.14.1
[json-v2.15.0]: https://github.com/ruby/json/releases/tag/v2.15.0
[json-v2.15.1]: https://github.com/ruby/json/releases/tag/v2.15.1
[json-v2.15.2]: https://github.com/ruby/json/releases/tag/v2.15.2
[json-v2.16.0]: https://github.com/ruby/json/releases/tag/v2.16.0
[json-v2.17.0]: https://github.com/ruby/json/releases/tag/v2.17.0
[json-v2.17.1]: https://github.com/ruby/json/releases/tag/v2.17.1
[json-v2.18.0]: https://github.com/ruby/json/releases/tag/v2.18.0
[net-http-v0.7.0]: https://github.com/ruby/net-http/releases/tag/v0.7.0
[net-http-v0.8.0]: https://github.com/ruby/net-http/releases/tag/v0.8.0
[net-http-v0.9.0]: https://github.com/ruby/net-http/releases/tag/v0.9.0
[net-http-v0.9.1]: https://github.com/ruby/net-http/releases/tag/v0.9.1
[openssl-v3.3.2]: https://github.com/ruby/openssl/releases/tag/v3.3.2
[openssl-v4.0.0]: https://github.com/ruby/openssl/releases/tag/v4.0.0
[optparse-v0.7.0]: https://github.com/ruby/optparse/releases/tag/v0.7.0
[optparse-v0.8.0]: https://github.com/ruby/optparse/releases/tag/v0.8.0
[optparse-v0.8.1]: https://github.com/ruby/optparse/releases/tag/v0.8.1
[pp-v0.6.3]: https://github.com/ruby/pp/releases/tag/v0.6.3
[prism-v1.6.0]: https://github.com/ruby/prism/releases/tag/v1.6.0
[prism-v1.7.0]: https://github.com/ruby/prism/releases/tag/v1.7.0
[psych-v5.2.3]: https://github.com/ruby/psych/releases/tag/v5.2.3
[psych-v5.2.4]: https://github.com/ruby/psych/releases/tag/v5.2.4
[psych-v5.2.5]: https://github.com/ruby/psych/releases/tag/v5.2.5
[psych-v5.2.6]: https://github.com/ruby/psych/releases/tag/v5.2.6
[psych-v5.3.0]: https://github.com/ruby/psych/releases/tag/v5.3.0
[psych-v5.3.1]: https://github.com/ruby/psych/releases/tag/v5.3.1
[resolv-v0.6.3]: https://github.com/ruby/resolv/releases/tag/v0.6.3
[resolv-v0.7.0]: https://github.com/ruby/resolv/releases/tag/v0.7.0
[stringio-v3.1.3]: https://github.com/ruby/stringio/releases/tag/v3.1.3
[stringio-v3.1.4]: https://github.com/ruby/stringio/releases/tag/v3.1.4
[stringio-v3.1.5]: https://github.com/ruby/stringio/releases/tag/v3.1.5
[stringio-v3.1.6]: https://github.com/ruby/stringio/releases/tag/v3.1.6
[stringio-v3.1.7]: https://github.com/ruby/stringio/releases/tag/v3.1.7
[stringio-v3.1.8]: https://github.com/ruby/stringio/releases/tag/v3.1.8
[stringio-v3.1.9]: https://github.com/ruby/stringio/releases/tag/v3.1.9
[stringio-v3.2.0]: https://github.com/ruby/stringio/releases/tag/v3.2.0
[strscan-v3.1.3]: https://github.com/ruby/strscan/releases/tag/v3.1.3
[strscan-v3.1.4]: https://github.com/ruby/strscan/releases/tag/v3.1.4
[strscan-v3.1.5]: https://github.com/ruby/strscan/releases/tag/v3.1.5
[strscan-v3.1.6]: https://github.com/ruby/strscan/releases/tag/v3.1.6
[time-v0.4.2]: https://github.com/ruby/time/releases/tag/v0.4.2
[timeout-v0.4.4]: https://github.com/ruby/timeout/releases/tag/v0.4.4
[timeout-v0.5.0]: https://github.com/ruby/timeout/releases/tag/v0.5.0
[timeout-v0.6.0]: https://github.com/ruby/timeout/releases/tag/v0.6.0
[uri-v1.1.0]: https://github.com/ruby/uri/releases/tag/v1.1.0
[uri-v1.1.1]: https://github.com/ruby/uri/releases/tag/v1.1.1
[weakref-v0.1.4]: https://github.com/ruby/weakref/releases/tag/v0.1.4
[zlib-v3.2.2]: https://github.com/ruby/zlib/releases/tag/v3.2.2
[power_assert-v3.0.0]: https://github.com/ruby/power_assert/releases/tag/v3.0.0
[power_assert-v3.0.1]: https://github.com/ruby/power_assert/releases/tag/v3.0.1
[rake-v13.3.0]: https://github.com/ruby/rake/releases/tag/v13.3.0
[rake-v13.3.1]: https://github.com/ruby/rake/releases/tag/v13.3.1
[test-unit-3.6.8]: https://github.com/test-unit/test-unit/releases/tag/3.6.8
[test-unit-3.6.9]: https://github.com/test-unit/test-unit/releases/tag/3.6.9
[test-unit-3.7.0]: https://github.com/test-unit/test-unit/releases/tag/3.7.0
[test-unit-3.7.1]: https://github.com/test-unit/test-unit/releases/tag/3.7.1
[test-unit-3.7.2]: https://github.com/test-unit/test-unit/releases/tag/3.7.2
[test-unit-3.7.3]: https://github.com/test-unit/test-unit/releases/tag/3.7.3
[test-unit-3.7.4]: https://github.com/test-unit/test-unit/releases/tag/3.7.4
[test-unit-3.7.5]: https://github.com/test-unit/test-unit/releases/tag/3.7.5
[rss-0.3.2]: https://github.com/ruby/rss/releases/tag/0.3.2
[net-ftp-v0.3.9]: https://github.com/ruby/net-ftp/releases/tag/v0.3.9
[net-imap-v0.5.9]: https://github.com/ruby/net-imap/releases/tag/v0.5.9
[net-imap-v0.5.10]: https://github.com/ruby/net-imap/releases/tag/v0.5.10
[net-imap-v0.5.11]: https://github.com/ruby/net-imap/releases/tag/v0.5.11
[net-imap-v0.5.12]: https://github.com/ruby/net-imap/releases/tag/v0.5.12
[net-imap-v0.5.13]: https://github.com/ruby/net-imap/releases/tag/v0.5.13
[net-imap-v0.6.0]: https://github.com/ruby/net-imap/releases/tag/v0.6.0
[net-imap-v0.6.1]: https://github.com/ruby/net-imap/releases/tag/v0.6.1
[net-imap-v0.6.2]: https://github.com/ruby/net-imap/releases/tag/v0.6.2
[net-smtp-v0.5.1]: https://github.com/ruby/net-smtp/releases/tag/v0.5.1
[matrix-v0.4.3]: https://github.com/ruby/matrix/releases/tag/v0.4.3
[prime-v0.1.4]: https://github.com/ruby/prime/releases/tag/v0.1.4
[rbs-v3.8.1]: https://github.com/ruby/rbs/releases/tag/v3.8.1
[rbs-v3.9.0.dev.1]: https://github.com/ruby/rbs/releases/tag/v3.9.0.dev.1
[rbs-v3.9.0.pre.1]: https://github.com/ruby/rbs/releases/tag/v3.9.0.pre.1
[rbs-v3.9.0.pre.2]: https://github.com/ruby/rbs/releases/tag/v3.9.0.pre.2
[rbs-v3.9.0]: https://github.com/ruby/rbs/releases/tag/v3.9.0
[rbs-v3.9.1]: https://github.com/ruby/rbs/releases/tag/v3.9.1
[rbs-v3.9.2]: https://github.com/ruby/rbs/releases/tag/v3.9.2
[rbs-v3.9.3]: https://github.com/ruby/rbs/releases/tag/v3.9.3
[rbs-v3.9.4]: https://github.com/ruby/rbs/releases/tag/v3.9.4
[rbs-v3.9.5]: https://github.com/ruby/rbs/releases/tag/v3.9.5
[rbs-v3.10.0.pre.1]: https://github.com/ruby/rbs/releases/tag/v3.10.0.pre.1
[rbs-v3.10.0.pre.2]: https://github.com/ruby/rbs/releases/tag/v3.10.0.pre.2
[rbs-v3.10.0]: https://github.com/ruby/rbs/releases/tag/v3.10.0
[debug-v1.11.1]: https://github.com/ruby/debug/releases/tag/v1.11.1
[base64-v0.3.0]: https://github.com/ruby/base64/releases/tag/v0.3.0
[bigdecimal-v3.2.0]: https://github.com/ruby/bigdecimal/releases/tag/v3.2.0
[bigdecimal-v3.2.1]: https://github.com/ruby/bigdecimal/releases/tag/v3.2.1
[bigdecimal-v3.2.2]: https://github.com/ruby/bigdecimal/releases/tag/v3.2.2
[bigdecimal-v3.2.3]: https://github.com/ruby/bigdecimal/releases/tag/v3.2.3
[bigdecimal-v3.3.0]: https://github.com/ruby/bigdecimal/releases/tag/v3.3.0
[bigdecimal-v3.3.1]: https://github.com/ruby/bigdecimal/releases/tag/v3.3.1
[bigdecimal-v4.0.0]: https://github.com/ruby/bigdecimal/releases/tag/v4.0.0
[bigdecimal-v4.0.1]: https://github.com/ruby/bigdecimal/releases/tag/v4.0.1
[drb-v2.2.3]: https://github.com/ruby/drb/releases/tag/v2.2.3
[syslog-v0.3.0]: https://github.com/ruby/syslog/releases/tag/v0.3.0
[csv-v3.3.3]: https://github.com/ruby/csv/releases/tag/v3.3.3
[csv-v3.3.4]: https://github.com/ruby/csv/releases/tag/v3.3.4
[csv-v3.3.5]: https://github.com/ruby/csv/releases/tag/v3.3.5
