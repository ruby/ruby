# NEWS for Ruby 3.3.0

This document is a list of user-visible feature changes
since the **3.2.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

## Core classes updates

Note: We're only listing outstanding class updates.

* Array

    * `Array#pack` now raises ArgumentError for unknown directives. [[Bug #19150]]

* String

    * `String#unpack` now raises ArgumentError for unknown directives. [[Bug #19150]]
    * `String#bytesplice` now accepts new arguments index/length or range of the source string to be copied.  [[Feature #19314]]

* ObjectSpace::WeakKeyMap

    * New core class to build collections with weak references.
      The class use equality semantic to lookup keys like a regular hash,
      but it doesn't hold strong references on the keys. [[Feature #18498]]

* Process.warnup

    * Notify the Ruby virtual machine that the boot sequence is finished,
      and that now is a good time to optimize the application. This is useful
      for long running applications. The actual optimizations performed are entirely
      implementation specific and may change in the future without notice. [[Feature #18885]

## Stdlib updates

The following default gems are updated.

* RubyGems 3.5.0.dev
* bigdecimal 3.1.4
* bundler 2.5.0.dev
* csv 3.2.7
* fiddle 1.1.2
* irb 1.6.3
* optparse 0.4.0.pre.1
* psych 5.1.0
* stringio 3.0.6
* strscan 3.0.7
* timeout 0.3.2

The following bundled gems are updated.

* minitest 5.18.0
* rbs 3.0.4
* typeprof 0.21.7

See GitHub releases like [Logger](https://github.com/ruby/logger/releases) or
changelog for details of the default gems or bundled gems.

## Supported platforms

## Compatibility issues

## Stdlib compatibility issues

## C API updates

## Implementation improvements

## JIT

[Bug #19150]:     https://bugs.ruby-lang.org/issues/19150
[Feature #19314]: https://bugs.ruby-lang.org/issues/19314
