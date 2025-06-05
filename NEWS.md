# NEWS for Ruby 3.5.0

This document is a list of user-visible feature changes
since the **3.4.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* `*nil` no longer calls `nil.to_a`, similar to how `**nil` does
  not call `nil.to_hash`.  [[Feature #21047]]

## Core classes updates

Note: We're only listing outstanding class updates.

* Binding

    * `Binding#local_variables` does no longer include numbered parameters.
      Also, `Binding#local_variable_get` and `Binding#local_variable_set` reject
      to handle numbered parameters.  [[Bug #21049]]

* IO

    * `IO.select` accepts +Float::INFINITY+ as a timeout argument.
      [[Feature #20610]]

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

* Set

    * Set is now a core class, instead of an autoloaded stdlib class.
      [[Feature #21216]]

* String

    * Update Unicode to Version 16.0.0 and Emoji Version 16.0.
      [[Feature #19908]][[Feature #20724]] (also applies to Regexp)

* Fiber::Scheduler

    * Introduce `Fiber::Scheduler#fiber_interrupt` to interrupt a fiber with a
      given exception. The initial use case is to interrupt a fiber that is
      waiting on a blocking IO operation when the IO operation is closed.
      [[Feature #21166]]

## Stdlib updates

The following bundled gems are promoted from default gems.

* ostruct 0.6.1
* pstore 0.2.0
* benchmark 0.4.1
* logger 1.7.0
* rdoc 6.14.0
* win32ole 1.9.2
* irb 1.15.2
* reline 0.6.1
* readline 0.0.4
* fiddle 1.1.8

We only list stdlib changes that are notable feature changes.

Other changes are listed in the following sections. We also listed release
history from the previous bundled version that is Ruby 3.3.0 if it has GitHub
releases.

The following default gem is added.

* win32-registry 0.1.0

The following default gems are updated.

* RubyGems 3.7.0.dev
* bundler 2.7.0.dev
* erb 5.0.1
* json 2.12.2
* optparse 0.7.0.dev.2
* prism 1.4.0
* psych 5.2.6
* stringio 3.1.8.dev
* strscan 3.1.5.dev
* uri 1.0.3

The following bundled gems are added.


The following bundled gems are updated.

* minitest 5.25.5
* rake 13.3.0
* test-unit 3.6.8
* rexml 3.4.1
* net-imap 0.5.8
* net-smtp 0.5.1
* rbs 3.9.4
* base64 0.3.0
* bigdecimal 3.2.2
* drb 2.2.3
* syslog 0.3.0
* csv 3.3.5
* repl_type_completor 0.1.11

## Supported platforms

## Compatibility issues

* The following methdos were removed from Ractor due because of `Ractor::Port`:

    * `Ractor.yield`
    * `Ractor#take`
    * `Ractor#close_incoming`
    * `Ractor#close_outgoging`

    [[Feature #21262]]

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

## Implementation improvements

## JIT

[Feature #18455]: https://bugs.ruby-lang.org/issues/18455
[Feature #19908]: https://bugs.ruby-lang.org/issues/19908
[Feature #20610]: https://bugs.ruby-lang.org/issues/20610
[Feature #20724]: https://bugs.ruby-lang.org/issues/20724
[Feature #21047]: https://bugs.ruby-lang.org/issues/21047
[Bug #21049]:     https://bugs.ruby-lang.org/issues/21049
[Feature #21166]: https://bugs.ruby-lang.org/issues/21166
[Feature #21216]: https://bugs.ruby-lang.org/issues/21216
[Feature #21258]: https://bugs.ruby-lang.org/issues/21258
[Feature #21262]: https://bugs.ruby-lang.org/issues/21262
[Feature #21287]: https://bugs.ruby-lang.org/issues/21287
