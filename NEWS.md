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
      Also, `Binding#local_variable_get` and `Binding#local_variable_set` reject to handle numbered parameters.
      [[Bug #21049]]

* IO

    * `IO.select` accepts +Float::INFINITY+ as a timeout argument.
      [[Feature #20610]]

* Set

    * Set is now a core class, instead of an autoloaded stdlib class.
      [[Feature #21216]]

* String

    * Update Unicode to Version 16.0.0 and Emoji Version 16.0. [[Feature #19908]][[Feature #20724]]
        (also applies to Regexp)

## Stdlib updates

The following bundled gems are promoted from default gems.

* ostruct 0.6.1
* pstore 0.2.0
* benchmark 0.4.0
* logger 1.7.0
* rdoc 6.13.1
* win32ole 1.9.2
* irb 1.15.2
* reline 0.6.1
* readline 0.0.4
* fiddle 1.1.8

We only list stdlib changes that are notable feature changes.

Other changes are listed in the following sections. we also listed release history from the previous bundled version that is Ruby 3.3.0 if it has GitHub releases.

The following default gem is added.

* win32-registry 0.1.0

The following default gems are updated.

* RubyGems 3.7.0.dev
* bundler 2.7.0.dev
* erb 5.0.1
* json 2.12.0
* optparse 0.7.0.dev.2
* prism 1.4.0
* psych 5.2.6
* stringio 3.1.8.dev
* strscan 3.1.5.dev
* uri 1.0.3

The following bundled gems are added.


The following bundled gems are updated.

* minitest 5.25.5
* test-unit 3.6.8
* rexml 3.4.1
* net-imap 0.5.8
* net-smtp 0.5.1
* rbs 3.9.4
* bigdecimal 3.1.9
* syslog 0.3.0
* csv 3.3.4
* repl_type_completor 0.1.11

## Supported platforms

## Compatibility issues

## Stdlib compatibility issues

* CGI library is removed from the default gems. Now we only provide `cgi/escape` for
  the following methods:
  * `CGI.escape` and `CGI.unescape`
  * `CGI.escapeHTML` and `CGI.unescapeHTML`
  * `CGI.escapeURIComponent` and `CGI.unescapeURIComponent`
  * `CGI.escapeElement` and `CGI.unescapeElement`
  [[Feature #21258]]

## C API updates

* IO

    * `rb_thread_fd_close` is deprecated and now a no-op. If you need to expose
      file descriptors from C extensions to Ruby code, create an `IO` instance
      using `RUBY_IO_MODE_EXTERNAL` and use `rb_io_close(io)` to close it (this
      also interrupts and waits for all pending operations on the `IO`
      instance). Directly closing file descriptors does not interrupt pending
      operations, and may lead to undefined beahviour. In other words, if two
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
[Feature #21216]: https://bugs.ruby-lang.org/issues/21216
[Feature #21258]: https://bugs.ruby-lang.org/issues/21258
