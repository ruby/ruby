# NEWS for Ruby 4.1.0

This document is a list of user-visible feature changes
since the **4.0.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

## Core classes updates

Note: We're only listing outstanding class updates.

* Method

    * `Method#source_location`, `Proc#source_location`, and
      `UnboundMethod#source_location` now return extended location
      information with 5 elements: `[path, start_line, start_column,
      end_line, end_column]`. The previous 2-element format `[path,
      line]` can still be obtained by calling `.take(2)` on the result.
      [[Feature #6012]]

* Set

    * A deprecated behavior, `Set#to_set`, `Range#to_set`, and
      `Enumerable#to_set` accepting arguments, was removed.  [[Feature #21390]]

## Stdlib updates

### The following bundled gems are added.


We only list stdlib changes that are notable feature changes.

Other changes are listed in the following sections. We also listed release
history from the previous bundled version that is Ruby 3.4.0 if it has GitHub
releases.

### The following bundled gem is promoted from default gems.

* tsort 0.2.0

### The following default gem is added.

### The following default gems are updated.

* RubyGems 4.1.0.dev
* bundler 4.1.0.dev
* stringio 3.2.1.dev
* strscan 3.1.7.dev

### The following bundled gems are updated.

* minitest 6.0.1
* test-unit 3.7.7
* rss 0.3.2
* net-imap 0.6.2
* rbs 3.10.2
* typeprof 0.31.1
* debug 1.11.1
* mutex_m 0.3.0
* rdoc 7.0.3

### RubyGems and Bundler

Ruby 4.0 bundled RubyGems and Bundler version 4. see the following links for details.

## Supported platforms

## Compatibility issues

## Stdlib compatibility issues

## C API updates

## Implementation improvements

### Ractor

A lot of work has gone into making Ractors more stable, performant, and usable. These improvements bring Ractor implementation closer to leaving experimental status.

## JIT

[Feature #6012]: https://bugs.ruby-lang.org/issues/6012
[Feature #21390]: https://bugs.ruby-lang.org/issues/21390
