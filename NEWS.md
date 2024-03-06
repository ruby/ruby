# NEWS for Ruby 3.4.0

This document is a list of user-visible feature changes
since the **3.3.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* `it` is added to reference a block parameter. [[Feature #18980]]

* Keyword splatting `nil` when calling methods is now supported.
  `**nil` is treated similar to `**{}`, passing no keywords,
  and not calling any conversion methods.
  [[Bug #20064]]

## Core classes updates

Note: We're only listing outstanding class updates.

## Stdlib updates

The following default gems are updated.

* RubyGems 3.6.0.dev
* bundler 2.6.0.dev
* erb 4.0.4
* fiddle 1.1.3
* io-console 0.7.2
* irb 1.11.2
* net-http 0.4.1
* prism 0.24.0
* reline 0.4.3
* stringio 3.1.1
* strscan 3.1.1

The following bundled gems are updated.

* minitest 5.22.2
* test-unit 3.6.2
* net-ftp 0.3.4
* net-imap 0.4.10
* net-smtp 0.4.0.1
* rbs 3.4.4
* typeprof 0.21.11
* debug 1.9.1

The following bundled gems are promoted from default gems.

* mutex_m 0.2.0
* getoptlong 0.2.1
* base64 0.2.0
* bigdecimal 3.1.6
* observer 0.1.2
* abbrev 0.1.2
* resolv-replace 0.1.1
* rinda 0.2.0
* drb 2.2.1
* nkf 0.2.0
* syslog 0.1.2
* csv 3.2.8

See GitHub releases like [GitHub Releases of Logger](https://github.com/ruby/logger/releases) or changelog for details of the default gems or bundled gems.

## Supported platforms

## Compatibility issues

* Error messages and backtrace displays have been changed.
  * Use a single quote instead of a backtick as a opening quote. [Feature #16495]
  * Display a class name before a method name (only when the class has a permanent name). [Feature #19117]
  * `Kernel#caller`, `Thread::Backtrace::Location`'s methods, etc. are also changed accordingly.
  ```
  Old:
  test.rb:1:in `foo': undefined method `time' for an instance of Integer
          from test.rb:2:in `<main>'

  New:
  test.rb:1:in 'Object#foo': undefined method 'time' for an instance of Integer
          from test.rb:2:in `<main>'
  ```

## Stdlib compatibility issues

## C API updates

## Implementation improvements

* `Array#each` is rewritten in Ruby for better performance [[Feature #20182]].

## JIT

[Feature #16495]: https://bugs.ruby-lang.org/issues/16495
[Feature #18980]: https://bugs.ruby-lang.org/issues/18980
[Feature #19117]: https://bugs.ruby-lang.org/issues/19117
[Bug #20064]:     https://bugs.ruby-lang.org/issues/20064
[Feature #20182]: https://bugs.ruby-lang.org/issues/20182
