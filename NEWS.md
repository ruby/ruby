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

## Stdlib updates

The following default gems are updated.

* RubyGems 3.5.0.dev
* abbrev 0.1.1
* bundler 2.5.0.dev
* csv 3.2.7
* fiddle 1.1.2
* optparse 0.4.0.pre.1
* stringio 3.0.5
* strscan 3.0.6

The following bundled gems are updated.

* minitest 5.17.0
* rbs 2.8.3
* typeprof 0.21.4

See GitHub releases like [Logger](https://github.com/ruby/logger/releases) or
changelog for details of the default gems or bundled gems.

## Supported platforms

## Compatibility issues

## Stdlib compatibility issues

## C API updates

## Implementation improvements

## JIT

[Bug #19150]:         https://bugs.ruby-lang.org/issues/19150
