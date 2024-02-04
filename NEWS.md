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
* irb 1.11.1
* net-http 0.4.1
* prism 0.20.0
* reline 0.4.2
* stringio 3.1.1
* strscan 3.0.9

The following bundled gems are updated.

* minitest 5.21.2
* net-ftp 0.3.4
* net-imap 0.4.9.1
* net-smtp 0.4.0.1
* rbs 3.4.3
* typeprof 0.21.9
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
* drb 2.2.0
* nkf 0.2.0
* syslog 0.1.2
* csv 3.2.8

See GitHub releases like [GitHub Releases of Logger](https://github.com/ruby/logger/releases) or changelog for details of the default gems or bundled gems.

## Supported platforms

## Compatibility issues

## Stdlib compatibility issues

## C API updates

## Implementation improvements

* `Array#each` is rewritten in Ruby for better performance [[Feature #20182]].

## JIT

[Feature #18980]: https://bugs.ruby-lang.org/issues/18980
[Bug #20064]:     https://bugs.ruby-lang.org/issues/20064
[Feature #20182]: https://bugs.ruby-lang.org/issues/20182
