# NEWS for Ruby 4.1.0

This document is a list of user-visible feature changes
since the **4.0.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

## Core classes updates

Note: We're only listing outstanding class updates.

* Kernel

    * `Kernel#autoload_relative` and `Module#autoload_relative` are added.
      These methods work like `autoload`, but resolve the file path relative
      to the file where the method is called, similar to `require_relative`.
      This makes it easier to autoload constants from files in the same
      directory without hardcoding absolute paths or manipulating `$LOAD_PATH`.
      [[Feature #15330]]

* Method

    * `Method#source_location`, `Proc#source_location`, and
      `UnboundMethod#source_location` now return extended location
      information with 5 elements: `[path, start_line, start_column,
      end_line, end_column]`. The previous 2-element format `[path,
      line]` can still be obtained by calling `.take(2)` on the result.
      [[Feature #6012]]
    * `Array#pack` accepts a new format `R` and `r` for unpacking unsigned
      and signed LEB128 encoded integers. [[Feature #21785]]

* Set

    * A deprecated behavior, `Set#to_set`, `Range#to_set`, and
      `Enumerable#to_set` accepting arguments, was removed.  [[Feature #21390]]

## Stdlib updates

### The following bundled gems are added.


We only list stdlib changes that are notable feature changes.

Other changes are listed in the following sections. We also listed release
history from the previous bundled version that is Ruby 3.4.0 if it has GitHub
releases.

### The following bundled gems are promoted from default gems.

* tsort 0.2.0
* win32-registry 0.1.2

### The following default gem is added.

### The following default gems are updated.

* RubyGems 4.1.0.dev
* bundler 4.1.0.dev
* json 2.18.1
  * 2.18.0 to [v2.18.1][json-v2.18.1]
* openssl 4.0.1
  * 4.0.0 to [v4.0.1][openssl-v4.0.1]
* prism 1.9.0
  * 1.8.0 to [v1.9.0][prism-v1.9.0]
* resolv 0.7.1
  * 0.7.0 to [v0.7.1][resolv-v0.7.1]
* stringio 3.2.1.dev
* strscan 3.1.7.dev
  * 3.1.6 to [v3.1.7][strscan-v3.1.7]
* syntax_suggest 2.0.3

### The following bundled gems are updated.

* minitest 6.0.2
* test-unit 3.7.7
  * 3.7.3 to [3.7.4][test-unit-3.7.4], [3.7.5][test-unit-3.7.5], [3.7.6][test-unit-3.7.6], [3.7.7][test-unit-3.7.7]
* rss 0.3.2
  * 0.3.1 to [0.3.2][rss-0.3.2]
* net-imap 0.6.3
  * 0.6.1 to [v0.6.2][net-imap-v0.6.2], [v0.6.3][net-imap-v0.6.3]
* rbs 3.10.3
  * 3.10.0 to [v3.10.1][rbs-v3.10.1], [v3.10.2][rbs-v3.10.2], [v3.10.3][rbs-v3.10.3]
* typeprof 0.31.1
* debug 1.11.1
  * 1.11.0 to [v1.11.1][debug-v1.11.1]
* mutex_m 0.3.0
* resolv-replace 0.2.0
  * 0.1.1 to [v0.2.0][resolv-replace-v0.2.0]
* syslog 0.4.0
  * 0.3.0 to [v0.4.0][syslog-v0.4.0]
* repl_type_completor 0.1.13
  * 0.1.12 to [v0.1.13][repl_type_completor-v0.1.13]
* pstore 0.2.1
  * 0.2.0 to [v0.2.1][pstore-v0.2.1]
* rdoc 7.2.0
  * 6.17.0 to [v7.0.0][rdoc-v7.0.0], [v7.0.1][rdoc-v7.0.1], [v7.0.2][rdoc-v7.0.2], [v7.0.3][rdoc-v7.0.3], [v7.1.0][rdoc-v7.1.0], [v7.2.0][rdoc-v7.2.0]
* win32ole 1.9.3
  * 1.9.2 to [v1.9.3][win32ole-v1.9.3]
* irb 1.17.0
  * 1.16.0 to [v1.17.0][irb-v1.17.0]

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
[Feature #15330]: https://bugs.ruby-lang.org/issues/15330
[Feature #21390]: https://bugs.ruby-lang.org/issues/21390
[Feature #21785]: https://bugs.ruby-lang.org/issues/21785
[json-v2.18.1]: https://github.com/ruby/json/releases/tag/v2.18.1
[openssl-v4.0.1]: https://github.com/ruby/openssl/releases/tag/v4.0.1
[prism-v1.9.0]: https://github.com/ruby/prism/releases/tag/v1.9.0
[resolv-v0.7.1]: https://github.com/ruby/resolv/releases/tag/v0.7.1
[strscan-v3.1.7]: https://github.com/ruby/strscan/releases/tag/v3.1.7
[test-unit-3.7.4]: https://github.com/test-unit/test-unit/releases/tag/3.7.4
[test-unit-3.7.5]: https://github.com/test-unit/test-unit/releases/tag/3.7.5
[test-unit-3.7.6]: https://github.com/test-unit/test-unit/releases/tag/3.7.6
[test-unit-3.7.7]: https://github.com/test-unit/test-unit/releases/tag/3.7.7
[rss-0.3.2]: https://github.com/ruby/rss/releases/tag/0.3.2
[net-imap-v0.6.2]: https://github.com/ruby/net-imap/releases/tag/v0.6.2
[net-imap-v0.6.3]: https://github.com/ruby/net-imap/releases/tag/v0.6.3
[rbs-v3.10.1]: https://github.com/ruby/rbs/releases/tag/v3.10.1
[rbs-v3.10.2]: https://github.com/ruby/rbs/releases/tag/v3.10.2
[rbs-v3.10.3]: https://github.com/ruby/rbs/releases/tag/v3.10.3
[debug-v1.11.1]: https://github.com/ruby/debug/releases/tag/v1.11.1
[resolv-replace-v0.2.0]: https://github.com/ruby/resolv-replace/releases/tag/v0.2.0
[syslog-v0.4.0]: https://github.com/ruby/syslog/releases/tag/v0.4.0
[repl_type_completor-v0.1.13]: https://github.com/ruby/repl_type_completor/releases/tag/v0.1.13
[pstore-v0.2.1]: https://github.com/ruby/pstore/releases/tag/v0.2.1
[rdoc-v7.0.0]: https://github.com/ruby/rdoc/releases/tag/v7.0.0
[rdoc-v7.0.1]: https://github.com/ruby/rdoc/releases/tag/v7.0.1
[rdoc-v7.0.2]: https://github.com/ruby/rdoc/releases/tag/v7.0.2
[rdoc-v7.0.3]: https://github.com/ruby/rdoc/releases/tag/v7.0.3
[rdoc-v7.1.0]: https://github.com/ruby/rdoc/releases/tag/v7.1.0
[rdoc-v7.2.0]: https://github.com/ruby/rdoc/releases/tag/v7.2.0
[win32ole-v1.9.3]: https://github.com/ruby/win32ole/releases/tag/v1.9.3
[irb-v1.17.0]: https://github.com/ruby/irb/releases/tag/v1.17.0
