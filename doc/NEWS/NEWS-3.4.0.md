# NEWS for Ruby 3.4.0

This document is a list of user-visible feature changes
since the **3.3.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* `it` is added to reference a block parameter. [[Feature #18980]]

* String literals in files without a `frozen_string_literal` comment now emit a deprecation warning
  when they are mutated.
  These warnings can be enabled with `-W:deprecated` or by setting `Warning[:deprecated] = true`.
  To disable this change, you can run Ruby with the `--disable-frozen-string-literal`
  command line argument. [[Feature #20205]]

    * `String#+@` now duplicates when mutating the string would emit
      a deprecation warning, offered as a replacement for the
      `str.dup if str.frozen?` pattern.

* Keyword splatting `nil` when calling methods is now supported.
  `**nil` is treated similarly to `**{}`, passing no keywords,
  and not calling any conversion methods.  [[Bug #20064]]

* Block passing is no longer allowed in index assignment
  (e.g. `a[0, &b] = 1`).  [[Bug #19918]]

* Keyword arguments are no longer allowed in index assignment
  (e.g. `a[0, kw: 1] = 2`).  [[Bug #20218]]

* The toplevel name `::Ruby` is reserved now, and the definition will be warned
  when `Warning[:deprecated]`.  [[Feature #20884]]

## Core classes updates

Note: We're only listing outstanding class updates.


* Array

    * `Array#fetch_values` was added. [[Feature #20702]]

* Exception

    * `Exception#set_backtrace` now accepts arrays of `Thread::Backtrace::Location`.
      `Kernel#raise`, `Thread#raise` and `Fiber#raise` also accept this new format. [[Feature #13557]]

* Fiber::Scheduler

    * An optional `Fiber::Scheduler#blocking_operation_wait` hook allows blocking operations to be moved out of the
      event loop in order to reduce latency and improve multi-core processor utilization. [[Feature #20876]]

* GC

    * `GC.config` added to allow setting configuration variables on the Garbage
      Collector. [[Feature #20443]]

    * GC configuration parameter `rgengc_allow_full_mark` introduced.  When `false`
      GC will only mark young objects. Default is `true`.  [[Feature #20443]]

* Hash

    * `Hash.new` now accepts an optional `capacity:` argument, to preallocate the hash with a given capacity.
      This can improve performance when building large hashes incrementally by saving on reallocation and
      rehashing of keys. [[Feature #19236]]

* IO::Buffer

    * `IO::Buffer#copy` can release the GVL, allowing other threads to run while copying data. [[Feature #20902]]

* Integer

    * `Integer#**` used to return `Float::INFINITY` when the return value is large, but now returns an `Integer`.
      If the return value is extremely large, it raises an exception.
      [[Feature #20811]]

* MatchData

    * `MatchData#bytebegin` and `MatchData#byteend` have been added. [[Feature #20576]]

* Object

    * `Object#singleton_method` now returns methods in modules prepended to or included in the
      receiver's singleton class. [[Bug #20620]]

        ```rb
        o = Object.new
        o.extend(Module.new{def a = 1})
        o.singleton_method(:a).call #=> 1
        ```

* Ractor

    * `require` in Ractor is allowed. The requiring process will be run on
      the main Ractor.
      `Ractor._require(feature)` is added to run requiring process on the
      main Ractor.
      [[Feature #20627]]

    * `Ractor.main?` is added. [[Feature #20627]]

    * `Ractor.[]` and `Ractor.[]=` are added to access the ractor local storage
      of the current Ractor. [[Feature #20715]]

    * `Ractor.store_if_absent(key){ init }` is added to initialize ractor local
      variables in thread-safety. [[Feature #20875]]

* Range

    * `Range#size` now raises `TypeError` if the range is not iterable. [[Misc #18984]]
    * `Range#step` now consistently has a semantics of iterating by using `+` operator
      for all types, not only numerics. [[Feature #18368]]

        ```ruby
        (Time.utc(2022, 2, 24)..).step(24*60*60).take(3)
        #=> [2022-02-24 00:00:00 UTC, 2022-02-25 00:00:00 UTC, 2022-02-26 00:00:00 UTC]
        ```

* Rational

    * `Rational#**` used to return `Float::INFINITY` or `Float::NAN`
      when the numerator of the return value is large, but now returns an `Rational`.
      If it is extremely large, it raises an exception. [[Feature #20811]]

* RubyVM::AbstractSyntaxTree

    * Add `RubyVM::AbstractSyntaxTree::Node#locations` method which returns location objects
      associated with the AST node. [[Feature #20624]]
    * Add `RubyVM::AbstractSyntaxTree::Location` class which holds location information. [[Feature #20624]]


* String

    * `String#append_as_bytes` was added to more easily and efficiently work with binary buffers and protocols.
      It directly concatenate the arguments into the string without any encoding validation or conversion.
      [[Feature #20594]]

* Symbol

    * The string returned by `Symbol#to_s` now emits a deprecation warning when mutated, and will be
      frozen in a future version of Ruby.
      These warnings can be enabled with `-W:deprecated` or by setting `Warning[:deprecated] = true`.
      [[Feature #20350]]

* Time

    * On Windows, now `Time#zone` encodes the system timezone name in UTF-8
      instead of the active code page, if it contains non-ASCII characters.
      [[Bug #20929]]

    * `Time#xmlschema`, and its `Time#iso8601` alias have been moved into the core Time
      class while previously it was an extension provided by the `time` gem. [[Feature #20707]]

* Warning

    * Add `Warning.categories` method which returns a list of possible warning categories.
      [[Feature #20293]]

## Stdlib updates

We only list stdlib changes that are notable feature changes.

* RubyGems
    * Add `--attestation` option to gem push. It enabled to store signature of build artifact to sigstore.dev.

* Bundler
    * Add a `lockfile_checksums` configuration to include checksums in fresh lockfiles.
    * Add bundle lock `--add-checksums` to add checksums to an existing lockfile.

* JSON

    * Performance improvements `JSON.parse` about 1.5 times faster than json-2.7.x.

* Tempfile

    * The keyword argument `anonymous: true` is implemented for Tempfile.create.
      `Tempfile.create(anonymous: true)` removes the created temporary file immediately.
      So applications don't need to remove the file.
      [[Feature #20497]]

* win32/sspi.rb

    * This library is now extracted from the Ruby repository to [ruby/net-http-sspi].
      [[Feature #20775]]

* Socket

    * `Socket::ResolutionError` and `Socket::ResolutionError#error_code` was added.
      [[Feature #20018]]

* IRB

    * Interactive method completion is now improved with type information by default.
      [[Feature #20778]]

Other changes are listed in the following sections. we also listed release history from the previous bundled version that is Ruby 3.3.0 if it has GitHub releases.

The following default gem is added.

* win32-registry 0.1.0

The following default gems are updated.

* [RubyGems][RubyGems] 3.6.2
    * 3.5.3 to [v3.5.4][RubyGems-v3.5.4], [v3.5.5][RubyGems-v3.5.5], [v3.5.6][RubyGems-v3.5.6], [v3.5.7][RubyGems-v3.5.7], [v3.5.8][RubyGems-v3.5.8], [v3.5.9][RubyGems-v3.5.9], [v3.5.10][RubyGems-v3.5.10], [v3.5.11][RubyGems-v3.5.11], [v3.5.12][RubyGems-v3.5.12], [v3.5.13][RubyGems-v3.5.13], [v3.5.14][RubyGems-v3.5.14], [v3.5.15][RubyGems-v3.5.15], [v3.5.16][RubyGems-v3.5.16], [v3.5.17][RubyGems-v3.5.17], [v3.5.18][RubyGems-v3.5.18], [v3.5.19][RubyGems-v3.5.19], [v3.5.20][RubyGems-v3.5.20], [v3.5.21][RubyGems-v3.5.21], [v3.5.22][RubyGems-v3.5.22], [v3.5.23][RubyGems-v3.5.23], [v3.6.0][RubyGems-v3.6.0], [v3.6.1][RubyGems-v3.6.1], [v3.6.2][RubyGems-v3.6.2]
* [benchmark][benchmark] 0.4.0
    * 0.3.0 to [v0.4.0][benchmark-v0.4.0]
* [bundler][bundler] 2.6.2
    * 2.5.3 to [v2.5.4][bundler-v2.5.4], [v2.5.5][bundler-v2.5.5], [v2.5.6][bundler-v2.5.6], [v2.5.7][bundler-v2.5.7], [v2.5.8][bundler-v2.5.8], [v2.5.9][bundler-v2.5.9], [v2.5.10][bundler-v2.5.10], [v2.5.11][bundler-v2.5.11], [v2.5.12][bundler-v2.5.12], [v2.5.13][bundler-v2.5.13], [v2.5.14][bundler-v2.5.14], [v2.5.15][bundler-v2.5.15], [v2.5.16][bundler-v2.5.16], [v2.5.17][bundler-v2.5.17], [v2.5.18][bundler-v2.5.18], [v2.5.19][bundler-v2.5.19], [v2.5.20][bundler-v2.5.20], [v2.5.21][bundler-v2.5.21], [v2.5.22][bundler-v2.5.22], [v2.5.23][bundler-v2.5.23], [v2.6.0][bundler-v2.6.0], [v2.6.1][bundler-v2.6.1], [v2.6.2][bundler-v2.6.2]
* [date][date] 3.4.1
    * 3.3.4 to [v3.4.0][date-v3.4.0], [v3.4.1][date-v3.4.1]
* [delegate][delegate] 0.4.0
    * 0.3.1 to [v0.4.0][delegate-v0.4.0]
* [did_you_mean][did_you_mean] 2.0.0
    * 1.6.3 to [v2.0.0][did_you_mean-v2.0.0]
* [digest][digest] 3.2.0
    * 3.1.1 to [v3.2.0.pre0][digest-v3.2.0.pre0], [v3.2.0][digest-v3.2.0]
* [erb][erb] 4.0.4
    * 4.0.3 to [v4.0.4][erb-v4.0.4]
* [error_highlight][error_highlight] 0.7.0
    * 0.6.0 to [v0.7.0][error_highlight-v0.7.0]
* [etc][etc] 1.4.5
    * 1.4.3 to [v1.4.4][etc-v1.4.4], [v1.4.5][etc-v1.4.5]
* [fcntl][fcntl] 1.2.0
    * 1.1.0 to [v1.2.0][fcntl-v1.2.0]
* [fiddle][fiddle] 1.1.6
    * 1.1.2 to [v1.1.3][fiddle-v1.1.3], [v1.1.4][fiddle-v1.1.4], [v1.1.5][fiddle-v1.1.5], [v1.1.6][fiddle-v1.1.6]
* [fileutils][fileutils] 1.7.3
    * 1.7.2 to [v1.7.3][fileutils-v1.7.3]
* [io-console][io-console] 0.8.0
    * 0.7.1 to [v0.7.2][io-console-v0.7.2], [v0.8.0.beta1][io-console-v0.8.0.beta1], [v0.8.0][io-console-v0.8.0]
* [io-nonblock][io-nonblock] 0.3.1
    * 0.3.0 to [v0.3.1][io-nonblock-v0.3.1]
* [ipaddr][ipaddr] 1.2.7
    * 1.2.6 to [v1.2.7][ipaddr-v1.2.7]
* [irb][irb] 1.14.3
    * 1.11.0 to [v1.11.1][irb-v1.11.1], [v1.11.2][irb-v1.11.2], [v1.12.0][irb-v1.12.0], [v1.13.0][irb-v1.13.0], [v1.13.1][irb-v1.13.1], [v1.13.2][irb-v1.13.2], [v1.14.0][irb-v1.14.0], [v1.14.1][irb-v1.14.1], [v1.14.2][irb-v1.14.2], [v1.14.3][irb-v1.14.3]
* [json][json] 2.9.1
    * 2.7.1 to [v2.7.2][json-v2.7.2], [v2.7.3.rc1][json-v2.7.3.rc1], [v2.7.3][json-v2.7.3], [v2.7.4][json-v2.7.4], [v2.7.5][json-v2.7.5], [v2.7.6][json-v2.7.6], [v2.8.0][json-v2.8.0], [v2.8.1][json-v2.8.1], [v2.8.2][json-v2.8.2], [v2.9.0][json-v2.9.0], [v2.9.1][json-v2.9.1]
* [logger][logger] 1.6.4
    * 1.6.0 to [v1.6.1][logger-v1.6.1], [v1.6.2][logger-v1.6.2], [v1.6.3][logger-v1.6.3], [v1.6.4][logger-v1.6.4]
* [net-http][net-http] 0.6.0
    * 0.4.0 to [v0.4.1][net-http-v0.4.1], [v0.5.0][net-http-v0.5.0], [v0.6.0][net-http-v0.6.0]
* [open-uri][open-uri] 0.5.0
    * 0.4.1 to [v0.5.0][open-uri-v0.5.0]
* [optparse][optparse] 0.6.0
    * 0.4.0 to [v0.5.0][optparse-v0.5.0], [v0.6.0][optparse-v0.6.0]
* [ostruct][ostruct] 0.6.1
    * 0.6.0 to [v0.6.1][ostruct-v0.6.1]
* [pathname][pathname] 0.4.0
    * 0.3.0 to [v0.4.0][pathname-v0.4.0]
* [pp][pp] 0.6.2
    * 0.5.0 to [v0.6.0][pp-v0.6.0], [v0.6.1][pp-v0.6.1], [v0.6.2][pp-v0.6.2]
* [prism][prism] 1.2.0
    * 0.19.0 to [v0.20.0][prism-v0.20.0], [v0.21.0][prism-v0.21.0], [v0.22.0][prism-v0.22.0], [v0.23.0][prism-v0.23.0], [v0.24.0][prism-v0.24.0], [v0.25.0][prism-v0.25.0], [v0.26.0][prism-v0.26.0], [v0.27.0][prism-v0.27.0], [v0.28.0][prism-v0.28.0], [v0.29.0][prism-v0.29.0], [v0.30.0][prism-v0.30.0], [v1.0.0][prism-v1.0.0], [v1.1.0][prism-v1.1.0], [v1.2.0][prism-v1.2.0]
* [pstore][pstore] 0.1.4
    * 0.1.3 to [v0.1.4][pstore-v0.1.4]
* [psych][psych] 5.2.2
    * 5.1.2 to [v5.2.0.beta1][psych-v5.2.0.beta1], [v5.2.0.beta2][psych-v5.2.0.beta2], [v5.2.0.beta3][psych-v5.2.0.beta3], [v5.2.0.beta4][psych-v5.2.0.beta4], [v5.2.0.beta5][psych-v5.2.0.beta5], [v5.2.0.beta6][psych-v5.2.0.beta6], [v5.2.0.beta7][psych-v5.2.0.beta7], [v5.2.0][psych-v5.2.0], [v5.2.1][psych-v5.2.1], [v5.2.2][psych-v5.2.2]
* [rdoc][rdoc] 6.10.0
    * 6.6.2 to [v6.7.0][rdoc-v6.7.0], [v6.8.0][rdoc-v6.8.0], [v6.8.1][rdoc-v6.8.1], [v6.9.0][rdoc-v6.9.0], [v6.9.1][rdoc-v6.9.1], [v6.10.0][rdoc-v6.10.0]
* [reline][reline] 0.6.0
    * 0.4.1 to [v0.4.2][reline-v0.4.2], [v0.4.3][reline-v0.4.3], [v0.5.0.pre.1][reline-v0.5.0.pre.1], [v0.5.0][reline-v0.5.0], [v0.5.1][reline-v0.5.1], [v0.5.2][reline-v0.5.2], [v0.5.3][reline-v0.5.3], [v0.5.4][reline-v0.5.4], [v0.5.5][reline-v0.5.5], [v0.5.6][reline-v0.5.6], [v0.5.7][reline-v0.5.7], [v0.5.8][reline-v0.5.8], [v0.5.9][reline-v0.5.9], [v0.5.10][reline-v0.5.10], [v0.5.11][reline-v0.5.11], [v0.5.12][reline-v0.5.12], [v0.6.0][reline-v0.6.0]
* [resolv][resolv] 0.6.0
    * 0.3.0 to [v0.4.0][resolv-v0.4.0], [v0.5.0][resolv-v0.5.0], [v0.6.0][resolv-v0.6.0]
* [securerandom][securerandom] 0.4.1
    * 0.3.1 to [v0.3.2][securerandom-v0.3.2], [v0.4.0][securerandom-v0.4.0], [v0.4.1][securerandom-v0.4.1]
* [set][set] 1.1.1
    * 1.1.0 to [v1.1.1][set-v1.1.1]
* [shellwords][shellwords] 0.2.2
    * 0.2.0 to [v0.2.1][shellwords-v0.2.1], [v0.2.2][shellwords-v0.2.2]
* [singleton][singleton] 0.3.0
    * 0.2.0 to [v0.3.0][singleton-v0.3.0]
* [stringio][stringio] 3.1.2
    * 3.1.0 to [v3.1.1][stringio-v3.1.1], [v3.1.2][stringio-v3.1.2]
* [strscan][strscan] 3.1.2
    * 3.0.7 to [v3.0.8][strscan-v3.0.8], [v3.0.9][strscan-v3.0.9], [v3.1.0][strscan-v3.1.0], [v3.1.1][strscan-v3.1.1], [v3.1.2][strscan-v3.1.2]
* [syntax_suggest][syntax_suggest] 2.0.2
    * 2.0.0 to [v2.0.1][syntax_suggest-v2.0.1], [v2.0.2][syntax_suggest-v2.0.2]
* [tempfile][tempfile] 0.3.1
    * 0.2.1 to [v0.3.0][tempfile-v0.3.0], [v0.3.1][tempfile-v0.3.1]
* [time][time] 0.4.1
    * 0.3.0 to [v0.4.0][time-v0.4.0], [v0.4.1][time-v0.4.1]
* [timeout][timeout] 0.4.3
    * 0.4.1 to [v0.4.2][timeout-v0.4.2], [v0.4.3][timeout-v0.4.3]
* [tmpdir][tmpdir] 0.3.1
    * 0.2.0 to [v0.3.0][tmpdir-v0.3.0], [v0.3.1][tmpdir-v0.3.1]
* [uri][uri] 1.0.2
    * 0.13.0 to [v0.13.1][uri-v0.13.1], [v1.0.0][uri-v1.0.0], [v1.0.1][uri-v1.0.1], [v1.0.2][uri-v1.0.2]
* [win32ole][win32ole] 1.9.1
    * 1.8.10 to [v1.9.0][win32ole-v1.9.0], [v1.9.1][win32ole-v1.9.1]
* [yaml][yaml] 0.4.0
    * 0.3.0 to [v0.4.0][yaml-v0.4.0]
* [zlib][zlib] 3.2.1
    * 3.1.0 to [v3.1.1][zlib-v3.1.1], [v3.2.0][zlib-v3.2.0], [v3.2.1][zlib-v3.2.1]

The following bundled gem is added.

* [repl_type_completor][repl_type_completor] 0.1.9

The following bundled gems are updated.

* [minitest][minitest] 5.25.4
    * 5.20.0 to [v5.25.4][minitest-v5.25.4]
* [power_assert][power_assert] 2.0.5
    * 2.0.3 to [v2.0.4][power_assert-v2.0.4], [v2.0.5][power_assert-v2.0.5]
* [rake][rake] 13.2.1
    * 13.1.0 to [v13.2.0][rake-v13.2.0], [v13.2.1][rake-v13.2.1]
* [test-unit][test-unit] 3.6.7
    * 3.6.1 to [3.6.2][test-unit-3.6.2], [3.6.3][test-unit-3.6.3], [3.6.4][test-unit-3.6.4], [3.6.5][test-unit-3.6.5], [3.6.6][test-unit-3.6.6], [3.6.7][test-unit-3.6.7]
* [rexml][rexml] 3.4.0
    * 3.2.6 to [v3.2.7][rexml-v3.2.7], [v3.2.8][rexml-v3.2.8], [v3.2.9][rexml-v3.2.9], [v3.3.0][rexml-v3.3.0], [v3.3.1][rexml-v3.3.1], [v3.3.2][rexml-v3.3.2], [v3.3.3][rexml-v3.3.3], [v3.3.4][rexml-v3.3.4], [v3.3.5][rexml-v3.3.5], [v3.3.6][rexml-v3.3.6], [v3.3.7][rexml-v3.3.7], [v3.3.8][rexml-v3.3.8], [v3.3.9][rexml-v3.3.9], [v3.4.0][rexml-v3.4.0]
* [rss][rss] 0.3.1
    * 0.3.0 to [0.3.1][rss-0.3.1]
* [net-ftp][net-ftp] 0.3.8
    * 0.3.3 to [v0.3.4][net-ftp-v0.3.4], [v0.3.5][net-ftp-v0.3.5], [v0.3.6][net-ftp-v0.3.6], [v0.3.7][net-ftp-v0.3.7], [v0.3.8][net-ftp-v0.3.8]
* [net-imap][net-imap] 0.5.4
    * 0.4.9 to [v0.4.9.1][net-imap-v0.4.9.1], [v0.4.10][net-imap-v0.4.10], [v0.4.11][net-imap-v0.4.11], [v0.4.12][net-imap-v0.4.12], [v0.4.13][net-imap-v0.4.13], [v0.4.14][net-imap-v0.4.14], [v0.4.15][net-imap-v0.4.15], [v0.4.16][net-imap-v0.4.16], [v0.4.17][net-imap-v0.4.17], [v0.5.0][net-imap-v0.5.0], [v0.4.18][net-imap-v0.4.18], [v0.5.1][net-imap-v0.5.1], [v0.5.2][net-imap-v0.5.2], [v0.5.3][net-imap-v0.5.3], [v0.5.4][net-imap-v0.5.4]
* [net-smtp][net-smtp] 0.5.0
    * 0.4.0 to [v0.4.0.1][net-smtp-v0.4.0.1], [v0.5.0][net-smtp-v0.5.0]
* [prime][prime] 0.1.3
    * 0.1.2 to [v0.1.3][prime-v0.1.3]
* [rbs][rbs] 3.8.0
    * 3.4.0 to [v3.4.1][rbs-v3.4.1], [v3.4.2][rbs-v3.4.2], [v3.4.3][rbs-v3.4.3], [v3.4.4][rbs-v3.4.4], [v3.5.0.pre.1][rbs-v3.5.0.pre.1], [v3.5.0.pre.2][rbs-v3.5.0.pre.2], [v3.5.0][rbs-v3.5.0], [v3.5.1][rbs-v3.5.1], [v3.5.2][rbs-v3.5.2], [v3.5.3][rbs-v3.5.3], [v3.6.0.dev.1][rbs-v3.6.0.dev.1], [v3.6.0.pre.1][rbs-v3.6.0.pre.1], [v3.6.0.pre.2][rbs-v3.6.0.pre.2], [v3.6.0.pre.3][rbs-v3.6.0.pre.3], [v3.6.0][rbs-v3.6.0], [v3.6.1][rbs-v3.6.1], [v3.7.0.dev.1][rbs-v3.7.0.dev.1], [v3.7.0.pre.1][rbs-v3.7.0.pre.1], [v3.7.0][rbs-v3.7.0], [v3.8.0.pre.1][rbs-v3.8.0.pre.1] [v3.8.0][rbs-v3.8.0]
* [typeprof][typeprof] 0.30.1
    * 0.21.9 to [v0.30.1][typeprof-v0.30.1]
* [debug][debug] 1.10.0
    * 1.9.1 to [v1.9.2][debug-v1.9.2], [v1.10.0][debug-v1.10.0]
* [racc][racc] 1.8.1
    * 1.7.3 to [v1.8.0][racc-v1.8.0], [v1.8.1][racc-v1.8.1]

The following bundled gems are promoted from default gems.

* [mutex_m][mutex_m] 0.3.0
    * 0.2.0 to [v0.3.0][mutex_m-v0.3.0]
* [getoptlong][getoptlong] 0.2.1
* [base64][base64] 0.2.0
* [bigdecimal][bigdecimal] 3.1.8
    * 3.1.5 to [v3.1.6][bigdecimal-v3.1.6], [v3.1.7][bigdecimal-v3.1.7], [v3.1.8][bigdecimal-v3.1.8]
* [observer][observer] 0.1.2
* [abbrev][abbrev] 0.1.2
* [resolv-replace][resolv-replace] 0.1.1
* [rinda][rinda] 0.2.0
* [drb][drb] 2.2.1
    * 2.2.0 to [v2.2.1][drb-v2.2.1]
* [nkf][nkf] 0.2.0
    * 0.1.3 to [v0.2.0][nkf-v0.2.0]
* [syslog][syslog] 0.2.0
    * 0.1.2 to [v0.2.0][syslog-v0.2.0]
* [csv][csv] 3.3.2
    * 3.2.8 to [v3.2.9][csv-v3.2.9], [v3.3.0][csv-v3.3.0], [v3.3.1][csv-v3.3.1], [v3.3.2][csv-v3.3.2]

## Supported platforms

## Compatibility issues

* Error messages and backtrace displays have been changed.

    * Use a single quote instead of a backtick as an opening quote. [[Feature #16495]]
    * Display a class name before a method name (only when the class has a permanent name). [[Feature #19117]]
    * Extra `rescue`/`ensure` frames are no longer available on the backtrace. [[Feature #20275]]
    * `Kernel#caller`, `Thread::Backtrace::Location`’s methods, etc. are also changed accordingly.

        Old:
        ```
        test.rb:1:in `foo': undefined method `time' for an instance of Integer
                from test.rb:2:in `<main>'
        ```

        New:
        ```
        test.rb:1:in 'Object#foo': undefined method 'time' for an instance of Integer
                from test.rb:2:in '<main>'
        ```

* `Hash#inspect` rendering have been changed. [[Bug #20433]]

    * Symbol keys are displayed using the modern symbol key syntax: `"{user: 1}"`
    * Other keys now have spaces around `=>`: `'{"user" => 1}'`, while previously they didn't: `'{"user"=>1}'`

* `Kernel#Float()` now accepts a decimal string with decimal part omitted. [[Feature #20705]]

    ```rb
    Float("1.")    #=> 1.0 (previously, an ArgumentError was raised)
    Float("1.E-1") #=> 0.1 (previously, an ArgumentError was raised)
    ```

* `String#to_f` now accepts a decimal string with decimal part omitted. [[Feature #20705]]
  Note that the result changes when an exponent is specified.

    ```rb
    "1.".to_f    #=> 1.0
    "1.E-1".to_f #=> 0.1 (previously, 1.0 was returned)
    ```

* `Refinement#refined_class` has been removed. [[Feature #19714]]

## Stdlib compatibility issues

* DidYouMean

    * `DidYouMean::SPELL_CHECKERS[]=` and `DidYouMean::SPELL_CHECKERS.merge!` are removed.

* Net::HTTP

    * Removed the following deprecated constants:
        * `Net::HTTP::ProxyMod`
        * `Net::NetPrivate::HTTPRequest`
        * `Net::HTTPInformationCode`
        * `Net::HTTPSuccessCode`
        * `Net::HTTPRedirectionCode`
        * `Net::HTTPRetriableCode`
        * `Net::HTTPClientErrorCode`
        * `Net::HTTPFatalErrorCode`
        * `Net::HTTPServerErrorCode`
        * `Net::HTTPResponseReceiver`
        * `Net::HTTPResponceReceiver`

      These constants were deprecated from 2012.

* Timeout

    * Reject negative values for `Timeout.timeout`. [[Bug #20795]]

* URI

    * Switched default parser to RFC 3986 compliant from RFC 2396 compliant.
      [[Bug #19266]]

## C API updates

* `rb_newobj` and `rb_newobj_of` (and corresponding macros `RB_NEWOBJ`, `RB_NEWOBJ_OF`, `NEWOBJ`, `NEWOBJ_OF`) have been removed. [[Feature #20265]]
* Removed deprecated function `rb_gc_force_recycle`. [[Feature #18290]]

## Implementation improvements

* The default parser is now Prism.
  To use the conventional parser, use the command-line argument `--parser=parse.y`.
  [[Feature #20564]]

* Happy Eyeballs version 2 (RFC8305), an algorithm that ensures faster and more reliable connections
  by attempting IPv6 and IPv4 concurrently, is used in `Socket.tcp` and `TCPSocket.new`.
  To disable it globally, set the environment variable `RUBY_TCP_NO_FAST_FALLBACK=1` or
  call `Socket.tcp_fast_fallback=false`.
  Or to disable it on a per-method basis, use the keyword argument `fast_fallback: false`.
  [[Feature #20108]] [[Feature #20782]]

* Alternative garbage collector (GC) implementations can be loaded dynamically
  through the modular garbage collector feature. To enable this feature,
  configure Ruby with `--with-modular-gc` at build time. GC libraries can be
  loaded at runtime using the environment variable `RUBY_GC_LIBRARY`.
  [[Feature #20351]]

* Ruby's built-in garbage collector has been split into a separate file at
  `gc/default/default.c` and interacts with Ruby using an API defined in
  `gc/gc_impl.h`. The built-in garbage collector can now also be built as a
  library using `make modular-gc MODULAR_GC=default` and enabled using the
  environment variable `RUBY_GC_LIBRARY=default`. [[Feature #20470]]

* An experimental GC library is provided based on [MMTk](https://www.mmtk.io/).
  This GC library can be built using `make modular-gc MODULAR_GC=mmtk` and
  enabled using the environment variable `RUBY_GC_LIBRARY=mmtk`. This requires
  the Rust toolchain on the build machine. [[Feature #20860]]

### YJIT

#### New features

* Command-line options
    * `--yjit-mem-size` introduces a unified memory limit (default 128MiB) to track total YJIT memory usage,
      providing a more intuitive alternative to the old `--yjit-exec-mem-size` option.
    * `--yjit-trace-exits=COUNTER` allows tracing of counted exits and fallbacks.
    * `--yjit-perf=codegen` allows profiling of JIT code based on YJIT's codegen functions.
    * `--yjit-log` enables a compilation log to track what gets compiled.
* Ruby API
    * `RubyVM::YJIT.enable(log: true)` also enables a compilation log.
    * `RubyVM::YJIT.log` provides access to the tail of the compilation log at run-time.
* YJIT stats
    * `RubyVM::YJIT.runtime_stats` now always provides additional statistics on
      invalidation, inlining, and metadata encoding.
    * `RubyVM::YJIT.runtime_stats[:iseq_calls]` is added to profile non-inlined Ruby method calls.
    * `RubyVM::YJIT.runtime_stats[:cfunc_calls]` is truncated to the top 20 entries for better performance.

#### New optimizations

* Compressed context reduces memory needed to store YJIT metadata
* Allocate registers for local variables and Ruby method arguments
* When YJIT is enabled, use more Core primitives written in Ruby:
    * `Array#each`, `Array#select`, `Array#map` rewritten in Ruby for better performance [[Feature #20182]].
* Ability to inline small/trivial methods such as:
    * Empty methods
    * Methods returning a constant
    * Methods returning `self`
    * Methods directly returning an argument
* Specialized codegen for many more runtime methods
* Optimize `String#getbyte`, `String#setbyte` and other string methods
* Optimize bitwise operations to speed up low-level bit/byte manipulation
* Support shareable constants in multi-ractor mode
* Various other incremental optimizations

## Miscellaneous changes

* Passing a block to a method which doesn't use the passed block will show
  a warning on verbose mode (`-w`).
  In connection with this, a new `strict_unused_block` warning category was introduced.
  Turn them on with `-W:strict_unused_block` or `Warning[:strict_unused_block] = true`.
  [[Feature #15554]]

* Redefining some core methods that are specially optimized by the interpreter
  and JIT like `String#freeze` or `Integer#+` now emits a performance class
  warning (`-W:performance` or `Warning[:performance] = true`).
  [[Feature #20429]]

[Feature #13557]: https://bugs.ruby-lang.org/issues/13557
[Feature #15554]: https://bugs.ruby-lang.org/issues/15554
[Feature #16495]: https://bugs.ruby-lang.org/issues/16495
[Feature #18290]: https://bugs.ruby-lang.org/issues/18290
[Feature #18368]: https://bugs.ruby-lang.org/issues/18368
[Feature #18980]: https://bugs.ruby-lang.org/issues/18980
[Misc #18984]:    https://bugs.ruby-lang.org/issues/18984
[Feature #19117]: https://bugs.ruby-lang.org/issues/19117
[Feature #19236]: https://bugs.ruby-lang.org/issues/19236
[Bug #19266]:     https://bugs.ruby-lang.org/issues/19266
[Feature #19714]: https://bugs.ruby-lang.org/issues/19714
[Bug #19918]:     https://bugs.ruby-lang.org/issues/19918
[Feature #20018]: https://bugs.ruby-lang.org/issues/20018
[Bug #20064]:     https://bugs.ruby-lang.org/issues/20064
[Feature #20108]: https://bugs.ruby-lang.org/issues/20108
[Feature #20182]: https://bugs.ruby-lang.org/issues/20182
[Feature #20205]: https://bugs.ruby-lang.org/issues/20205
[Bug #20218]:     https://bugs.ruby-lang.org/issues/20218
[Feature #20265]: https://bugs.ruby-lang.org/issues/20265
[Feature #20275]: https://bugs.ruby-lang.org/issues/20275
[Feature #20293]: https://bugs.ruby-lang.org/issues/20293
[Feature #20350]: https://bugs.ruby-lang.org/issues/20350
[Feature #20351]: https://bugs.ruby-lang.org/issues/20351
[Feature #20429]: https://bugs.ruby-lang.org/issues/20429
[Bug #20433]:     https://bugs.ruby-lang.org/issues/20433
[Feature #20443]: https://bugs.ruby-lang.org/issues/20443
[Feature #20470]: https://bugs.ruby-lang.org/issues/20470
[Feature #20497]: https://bugs.ruby-lang.org/issues/20497
[Feature #20564]: https://bugs.ruby-lang.org/issues/20564
[Feature #20576]: https://bugs.ruby-lang.org/issues/20576
[Feature #20594]: https://bugs.ruby-lang.org/issues/20594
[Bug #20620]:     https://bugs.ruby-lang.org/issues/20620
[Feature #20624]: https://bugs.ruby-lang.org/issues/20624
[Feature #20627]: https://bugs.ruby-lang.org/issues/20627
[Feature #20702]: https://bugs.ruby-lang.org/issues/20702
[Feature #20705]: https://bugs.ruby-lang.org/issues/20705
[Feature #20707]: https://bugs.ruby-lang.org/issues/20707
[Feature #20715]: https://bugs.ruby-lang.org/issues/20715
[Feature #20775]: https://bugs.ruby-lang.org/issues/20775
[Feature #20778]: https://bugs.ruby-lang.org/issues/20778
[Feature #20782]: https://bugs.ruby-lang.org/issues/20782
[Bug #20795]:     https://bugs.ruby-lang.org/issues/20795
[Feature #20811]: https://bugs.ruby-lang.org/issues/20811
[Feature #20860]: https://bugs.ruby-lang.org/issues/20860
[Feature #20875]: https://bugs.ruby-lang.org/issues/20875
[Feature #20876]: https://bugs.ruby-lang.org/issues/20876
[Feature #20884]: https://bugs.ruby-lang.org/issues/20884
[Feature #20902]: https://bugs.ruby-lang.org/issues/20902
[Bug #20929]:     https://bugs.ruby-lang.org/issues/20929
[RubyGems-v3.5.4]: https://github.com/rubygems/rubygems/releases/tag/v3.5.4
[RubyGems-v3.5.5]: https://github.com/rubygems/rubygems/releases/tag/v3.5.5
[RubyGems-v3.5.6]: https://github.com/rubygems/rubygems/releases/tag/v3.5.6
[RubyGems-v3.5.7]: https://github.com/rubygems/rubygems/releases/tag/v3.5.7
[RubyGems-v3.5.8]: https://github.com/rubygems/rubygems/releases/tag/v3.5.8
[RubyGems-v3.5.9]: https://github.com/rubygems/rubygems/releases/tag/v3.5.9
[RubyGems-v3.5.10]: https://github.com/rubygems/rubygems/releases/tag/v3.5.10
[RubyGems-v3.5.11]: https://github.com/rubygems/rubygems/releases/tag/v3.5.11
[RubyGems-v3.5.12]: https://github.com/rubygems/rubygems/releases/tag/v3.5.12
[RubyGems-v3.5.13]: https://github.com/rubygems/rubygems/releases/tag/v3.5.13
[RubyGems-v3.5.14]: https://github.com/rubygems/rubygems/releases/tag/v3.5.14
[RubyGems-v3.5.15]: https://github.com/rubygems/rubygems/releases/tag/v3.5.15
[RubyGems-v3.5.16]: https://github.com/rubygems/rubygems/releases/tag/v3.5.16
[RubyGems-v3.5.17]: https://github.com/rubygems/rubygems/releases/tag/v3.5.17
[RubyGems-v3.5.18]: https://github.com/rubygems/rubygems/releases/tag/v3.5.18
[RubyGems-v3.5.19]: https://github.com/rubygems/rubygems/releases/tag/v3.5.19
[RubyGems-v3.5.20]: https://github.com/rubygems/rubygems/releases/tag/v3.5.20
[RubyGems-v3.5.21]: https://github.com/rubygems/rubygems/releases/tag/v3.5.21
[RubyGems-v3.5.22]: https://github.com/rubygems/rubygems/releases/tag/v3.5.22
[RubyGems-v3.5.23]: https://github.com/rubygems/rubygems/releases/tag/v3.5.23
[RubyGems-v3.6.0]: https://github.com/rubygems/rubygems/releases/tag/v3.6.0
[RubyGems-v3.6.1]: https://github.com/rubygems/rubygems/releases/tag/v3.6.1
[RubyGems-v3.6.2]: https://github.com/rubygems/rubygems/releases/tag/v3.6.2
[benchmark-v0.4.0]: https://github.com/ruby/benchmark/releases/tag/v0.4.0
[bundler-v2.5.4]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.4
[bundler-v2.5.5]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.5
[bundler-v2.5.6]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.6
[bundler-v2.5.7]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.7
[bundler-v2.5.8]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.8
[bundler-v2.5.9]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.9
[bundler-v2.5.10]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.10
[bundler-v2.5.11]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.11
[bundler-v2.5.12]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.12
[bundler-v2.5.13]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.13
[bundler-v2.5.14]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.14
[bundler-v2.5.15]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.15
[bundler-v2.5.16]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.16
[bundler-v2.5.17]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.17
[bundler-v2.5.18]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.18
[bundler-v2.5.19]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.19
[bundler-v2.5.20]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.20
[bundler-v2.5.21]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.21
[bundler-v2.5.22]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.22
[bundler-v2.5.23]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.5.23
[bundler-v2.6.0]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.6.0
[bundler-v2.6.1]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.6.1
[bundler-v2.6.2]: https://github.com/rubygems/rubygems/releases/tag/bundler-v2.6.2
[date-v3.4.0]: https://github.com/ruby/date/releases/tag/v3.4.0
[date-v3.4.1]: https://github.com/ruby/date/releases/tag/v3.4.1
[delegate-v0.4.0]: https://github.com/ruby/delegate/releases/tag/v0.4.0
[did_you_mean-v2.0.0]: https://github.com/ruby/did_you_mean/releases/tag/v2.0.0
[digest-v3.2.0.pre0]: https://github.com/ruby/digest/releases/tag/v3.2.0.pre0
[digest-v3.2.0]: https://github.com/ruby/digest/releases/tag/v3.2.0
[erb-v4.0.4]: https://github.com/ruby/erb/releases/tag/v4.0.4
[etc-v1.4.4]: https://github.com/ruby/etc/releases/tag/v1.4.4
[etc-v1.4.5]: https://github.com/ruby/etc/releases/tag/v1.4.5
[fcntl-v1.2.0]: https://github.com/ruby/fcntl/releases/tag/v1.2.0
[fiddle-v1.1.3]: https://github.com/ruby/fiddle/releases/tag/v1.1.3
[fiddle-v1.1.4]: https://github.com/ruby/fiddle/releases/tag/v1.1.4
[fiddle-v1.1.5]: https://github.com/ruby/fiddle/releases/tag/v1.1.5
[fiddle-v1.1.6]: https://github.com/ruby/fiddle/releases/tag/v1.1.6
[fileutils-v1.7.3]: https://github.com/ruby/fileutils/releases/tag/v1.7.3
[io-console-v0.7.2]: https://github.com/ruby/io-console/releases/tag/v0.7.2
[io-console-v0.8.0.beta1]: https://github.com/ruby/io-console/releases/tag/v0.8.0.beta1
[io-console-v0.8.0]: https://github.com/ruby/io-console/releases/tag/v0.8.0
[io-nonblock-v0.3.1]: https://github.com/ruby/io-nonblock/releases/tag/v0.3.1
[ipaddr-v1.2.7]: https://github.com/ruby/ipaddr/releases/tag/v1.2.7
[irb-v1.11.1]: https://github.com/ruby/irb/releases/tag/v1.11.1
[irb-v1.11.2]: https://github.com/ruby/irb/releases/tag/v1.11.2
[irb-v1.12.0]: https://github.com/ruby/irb/releases/tag/v1.12.0
[irb-v1.13.0]: https://github.com/ruby/irb/releases/tag/v1.13.0
[irb-v1.13.1]: https://github.com/ruby/irb/releases/tag/v1.13.1
[irb-v1.13.2]: https://github.com/ruby/irb/releases/tag/v1.13.2
[irb-v1.14.0]: https://github.com/ruby/irb/releases/tag/v1.14.0
[irb-v1.14.1]: https://github.com/ruby/irb/releases/tag/v1.14.1
[irb-v1.14.2]: https://github.com/ruby/irb/releases/tag/v1.14.2
[irb-v1.14.3]: https://github.com/ruby/irb/releases/tag/v1.14.3
[json-v2.7.2]: https://github.com/ruby/json/releases/tag/v2.7.2
[json-v2.7.3.rc1]: https://github.com/ruby/json/releases/tag/v2.7.3.rc1
[json-v2.7.3]: https://github.com/ruby/json/releases/tag/v2.7.3
[json-v2.7.4]: https://github.com/ruby/json/releases/tag/v2.7.4
[json-v2.7.5]: https://github.com/ruby/json/releases/tag/v2.7.5
[json-v2.7.6]: https://github.com/ruby/json/releases/tag/v2.7.6
[json-v2.8.0]: https://github.com/ruby/json/releases/tag/v2.8.0
[json-v2.8.1]: https://github.com/ruby/json/releases/tag/v2.8.1
[json-v2.8.2]: https://github.com/ruby/json/releases/tag/v2.8.2
[json-v2.9.0]: https://github.com/ruby/json/releases/tag/v2.9.0
[json-v2.9.1]: https://github.com/ruby/json/releases/tag/v2.9.1
[logger-v1.6.1]: https://github.com/ruby/logger/releases/tag/v1.6.1
[logger-v1.6.2]: https://github.com/ruby/logger/releases/tag/v1.6.2
[logger-v1.6.3]: https://github.com/ruby/logger/releases/tag/v1.6.3
[logger-v1.6.4]: https://github.com/ruby/logger/releases/tag/v1.6.4
[net-http-v0.4.1]: https://github.com/ruby/net-http/releases/tag/v0.4.1
[net-http-v0.5.0]: https://github.com/ruby/net-http/releases/tag/v0.5.0
[net-http-v0.6.0]: https://github.com/ruby/net-http/releases/tag/v0.6.0
[open-uri-v0.5.0]: https://github.com/ruby/open-uri/releases/tag/v0.5.0
[optparse-v0.5.0]: https://github.com/ruby/optparse/releases/tag/v0.5.0
[optparse-v0.6.0]: https://github.com/ruby/optparse/releases/tag/v0.6.0
[ostruct-v0.6.1]: https://github.com/ruby/ostruct/releases/tag/v0.6.1
[pathname-v0.4.0]: https://github.com/ruby/pathname/releases/tag/v0.4.0
[pp-v0.6.0]: https://github.com/ruby/pp/releases/tag/v0.6.0
[pp-v0.6.1]: https://github.com/ruby/pp/releases/tag/v0.6.1
[pp-v0.6.2]: https://github.com/ruby/pp/releases/tag/v0.6.2
[prism-v0.20.0]: https://github.com/ruby/prism/releases/tag/v0.20.0
[prism-v0.21.0]: https://github.com/ruby/prism/releases/tag/v0.21.0
[prism-v0.22.0]: https://github.com/ruby/prism/releases/tag/v0.22.0
[prism-v0.23.0]: https://github.com/ruby/prism/releases/tag/v0.23.0
[prism-v0.24.0]: https://github.com/ruby/prism/releases/tag/v0.24.0
[prism-v0.25.0]: https://github.com/ruby/prism/releases/tag/v0.25.0
[prism-v0.26.0]: https://github.com/ruby/prism/releases/tag/v0.26.0
[prism-v0.27.0]: https://github.com/ruby/prism/releases/tag/v0.27.0
[prism-v0.28.0]: https://github.com/ruby/prism/releases/tag/v0.28.0
[prism-v0.29.0]: https://github.com/ruby/prism/releases/tag/v0.29.0
[prism-v0.30.0]: https://github.com/ruby/prism/releases/tag/v0.30.0
[prism-v1.0.0]: https://github.com/ruby/prism/releases/tag/v1.0.0
[prism-v1.1.0]: https://github.com/ruby/prism/releases/tag/v1.1.0
[prism-v1.2.0]: https://github.com/ruby/prism/releases/tag/v1.2.0
[pstore-v0.1.4]: https://github.com/ruby/pstore/releases/tag/v0.1.4
[psych-v5.2.0.beta1]: https://github.com/ruby/psych/releases/tag/v5.2.0.beta1
[psych-v5.2.0]: https://github.com/ruby/psych/releases/tag/v5.2.0
[psych-v5.2.0.beta2]: https://github.com/ruby/psych/releases/tag/v5.2.0.beta2
[psych-v5.2.0.beta3]: https://github.com/ruby/psych/releases/tag/v5.2.0.beta3
[psych-v5.2.0.beta4]: https://github.com/ruby/psych/releases/tag/v5.2.0.beta4
[psych-v5.2.0.beta5]: https://github.com/ruby/psych/releases/tag/v5.2.0.beta5
[psych-v5.2.0.beta6]: https://github.com/ruby/psych/releases/tag/v5.2.0.beta6
[psych-v5.2.0.beta7]: https://github.com/ruby/psych/releases/tag/v5.2.0.beta7
[psych-v5.2.1]: https://github.com/ruby/psych/releases/tag/v5.2.1
[psych-v5.2.2]: https://github.com/ruby/psych/releases/tag/v5.2.2
[rdoc-v6.7.0]: https://github.com/ruby/rdoc/releases/tag/v6.7.0
[rdoc-v6.8.0]: https://github.com/ruby/rdoc/releases/tag/v6.8.0
[rdoc-v6.8.1]: https://github.com/ruby/rdoc/releases/tag/v6.8.1
[rdoc-v6.9.0]: https://github.com/ruby/rdoc/releases/tag/v6.9.0
[rdoc-v6.9.1]: https://github.com/ruby/rdoc/releases/tag/v6.9.1
[rdoc-v6.10.0]: https://github.com/ruby/rdoc/releases/tag/v6.10.0
[reline-v0.5.0.pre.1]: https://github.com/ruby/reline/releases/tag/v0.5.0.pre.1
[reline-v0.4.2]: https://github.com/ruby/reline/releases/tag/v0.4.2
[reline-v0.4.3]: https://github.com/ruby/reline/releases/tag/v0.4.3
[reline-v0.5.0]: https://github.com/ruby/reline/releases/tag/v0.5.0
[reline-v0.5.1]: https://github.com/ruby/reline/releases/tag/v0.5.1
[reline-v0.5.2]: https://github.com/ruby/reline/releases/tag/v0.5.2
[reline-v0.5.3]: https://github.com/ruby/reline/releases/tag/v0.5.3
[reline-v0.5.4]: https://github.com/ruby/reline/releases/tag/v0.5.4
[reline-v0.5.5]: https://github.com/ruby/reline/releases/tag/v0.5.5
[reline-v0.5.6]: https://github.com/ruby/reline/releases/tag/v0.5.6
[reline-v0.5.7]: https://github.com/ruby/reline/releases/tag/v0.5.7
[reline-v0.5.8]: https://github.com/ruby/reline/releases/tag/v0.5.8
[reline-v0.5.9]: https://github.com/ruby/reline/releases/tag/v0.5.9
[reline-v0.5.10]: https://github.com/ruby/reline/releases/tag/v0.5.10
[reline-v0.5.11]: https://github.com/ruby/reline/releases/tag/v0.5.11
[reline-v0.5.12]: https://github.com/ruby/reline/releases/tag/v0.5.12
[reline-v0.6.0]: https://github.com/ruby/reline/releases/tag/v0.6.0
[resolv-v0.4.0]: https://github.com/ruby/resolv/releases/tag/v0.4.0
[resolv-v0.5.0]: https://github.com/ruby/resolv/releases/tag/v0.5.0
[resolv-v0.6.0]: https://github.com/ruby/resolv/releases/tag/v0.6.0
[securerandom-v0.3.2]: https://github.com/ruby/securerandom/releases/tag/v0.3.2
[securerandom-v0.4.0]: https://github.com/ruby/securerandom/releases/tag/v0.4.0
[securerandom-v0.4.1]: https://github.com/ruby/securerandom/releases/tag/v0.4.1
[set-v1.1.1]: https://github.com/ruby/set/releases/tag/v1.1.1
[shellwords-v0.2.1]: https://github.com/ruby/shellwords/releases/tag/v0.2.1
[shellwords-v0.2.2]: https://github.com/ruby/shellwords/releases/tag/v0.2.2
[singleton-v0.3.0]: https://github.com/ruby/singleton/releases/tag/v0.3.0
[stringio-v3.1.1]: https://github.com/ruby/stringio/releases/tag/v3.1.1
[stringio-v3.1.2]: https://github.com/ruby/stringio/releases/tag/v3.1.2
[strscan-v3.0.8]: https://github.com/ruby/strscan/releases/tag/v3.0.8
[strscan-v3.0.9]: https://github.com/ruby/strscan/releases/tag/v3.0.9
[strscan-v3.1.0]: https://github.com/ruby/strscan/releases/tag/v3.1.0
[strscan-v3.1.1]: https://github.com/ruby/strscan/releases/tag/v3.1.1
[strscan-v3.1.2]: https://github.com/ruby/strscan/releases/tag/v3.1.2
[syntax_suggest-v2.0.1]: https://github.com/ruby/syntax_suggest/releases/tag/v2.0.1
[syntax_suggest-v2.0.2]: https://github.com/ruby/syntax_suggest/releases/tag/v2.0.2
[tempfile-v0.3.0]: https://github.com/ruby/tempfile/releases/tag/v0.3.0
[tempfile-v0.3.1]: https://github.com/ruby/tempfile/releases/tag/v0.3.1
[time-v0.4.0]: https://github.com/ruby/time/releases/tag/v0.4.0
[time-v0.4.1]: https://github.com/ruby/time/releases/tag/v0.4.1
[timeout-v0.4.2]: https://github.com/ruby/timeout/releases/tag/v0.4.2
[timeout-v0.4.3]: https://github.com/ruby/timeout/releases/tag/v0.4.3
[tmpdir-v0.3.0]: https://github.com/ruby/tmpdir/releases/tag/v0.3.0
[tmpdir-v0.3.1]: https://github.com/ruby/tmpdir/releases/tag/v0.3.1
[uri-v0.13.1]: https://github.com/ruby/uri/releases/tag/v0.13.1
[uri-v1.0.0]: https://github.com/ruby/uri/releases/tag/v1.0.0
[uri-v1.0.1]: https://github.com/ruby/uri/releases/tag/v1.0.1
[uri-v1.0.2]: https://github.com/ruby/uri/releases/tag/v1.0.2
[win32ole-v1.9.0]: https://github.com/ruby/win32ole/releases/tag/v1.9.0
[win32ole-v1.9.1]: https://github.com/ruby/win32ole/releases/tag/v1.9.1
[yaml-v0.4.0]: https://github.com/ruby/yaml/releases/tag/v0.4.0
[zlib-v3.1.1]: https://github.com/ruby/zlib/releases/tag/v3.1.1
[zlib-v3.2.0]: https://github.com/ruby/zlib/releases/tag/v3.2.0
[zlib-v3.2.1]: https://github.com/ruby/zlib/releases/tag/v3.2.1
[minitest-v5.25.4]: https://github.com/seattlerb/minitest/releases/tag/v5.25.4
[power_assert-v2.0.4]:  https://github.com/ruby/power_assert/releases/tag/v2.0.4
[power_assert-v2.0.5]:  https://github.com/ruby/power_assert/releases/tag/v2.0.5
[rake-v13.2.0]: https://github.com/ruby/rake/releases/tag/v13.2.0
[rake-v13.2.1]: https://github.com/ruby/rake/releases/tag/v13.2.1
[test-unit-3.6.2]: https://github.com/test-unit/test-unit/releases/tag/3.6.2
[test-unit-3.6.3]: https://github.com/test-unit/test-unit/releases/tag/3.6.3
[test-unit-3.6.4]: https://github.com/test-unit/test-unit/releases/tag/3.6.4
[test-unit-3.6.5]: https://github.com/test-unit/test-unit/releases/tag/3.6.5
[test-unit-3.6.6]: https://github.com/test-unit/test-unit/releases/tag/3.6.6
[test-unit-3.6.7]: https://github.com/test-unit/test-unit/releases/tag/3.6.7
[rexml-v3.2.7]: https://github.com/ruby/rexml/releases/tag/v3.2.7
[rexml-v3.2.8]: https://github.com/ruby/rexml/releases/tag/v3.2.8
[rexml-v3.2.9]: https://github.com/ruby/rexml/releases/tag/v3.2.9
[rexml-v3.3.0]: https://github.com/ruby/rexml/releases/tag/v3.3.0
[rexml-v3.3.1]: https://github.com/ruby/rexml/releases/tag/v3.3.1
[rexml-v3.3.2]: https://github.com/ruby/rexml/releases/tag/v3.3.2
[rexml-v3.3.3]: https://github.com/ruby/rexml/releases/tag/v3.3.3
[rexml-v3.3.4]: https://github.com/ruby/rexml/releases/tag/v3.3.4
[rexml-v3.3.5]: https://github.com/ruby/rexml/releases/tag/v3.3.5
[rexml-v3.3.6]: https://github.com/ruby/rexml/releases/tag/v3.3.6
[rexml-v3.3.7]: https://github.com/ruby/rexml/releases/tag/v3.3.7
[rexml-v3.3.8]: https://github.com/ruby/rexml/releases/tag/v3.3.8
[rexml-v3.3.9]: https://github.com/ruby/rexml/releases/tag/v3.3.9
[rexml-v3.4.0]: https://github.com/ruby/rexml/releases/tag/v3.4.0
[rss-0.3.1]: https://github.com/ruby/rss/releases/tag/0.3.1
[net-ftp-v0.3.4]: https://github.com/ruby/net-ftp/releases/tag/v0.3.4
[net-ftp-v0.3.5]: https://github.com/ruby/net-ftp/releases/tag/v0.3.5
[net-ftp-v0.3.6]: https://github.com/ruby/net-ftp/releases/tag/v0.3.6
[net-ftp-v0.3.7]: https://github.com/ruby/net-ftp/releases/tag/v0.3.7
[net-ftp-v0.3.8]: https://github.com/ruby/net-ftp/releases/tag/v0.3.8
[net-imap-v0.4.9.1]: https://github.com/ruby/net-imap/releases/tag/v0.4.9.1
[net-imap-v0.4.10]: https://github.com/ruby/net-imap/releases/tag/v0.4.10
[net-imap-v0.4.11]: https://github.com/ruby/net-imap/releases/tag/v0.4.11
[net-imap-v0.4.12]: https://github.com/ruby/net-imap/releases/tag/v0.4.12
[net-imap-v0.4.13]: https://github.com/ruby/net-imap/releases/tag/v0.4.13
[net-imap-v0.4.14]: https://github.com/ruby/net-imap/releases/tag/v0.4.14
[net-imap-v0.4.15]: https://github.com/ruby/net-imap/releases/tag/v0.4.15
[net-imap-v0.4.16]: https://github.com/ruby/net-imap/releases/tag/v0.4.16
[net-imap-v0.4.17]: https://github.com/ruby/net-imap/releases/tag/v0.4.17
[net-imap-v0.5.0]: https://github.com/ruby/net-imap/releases/tag/v0.5.0
[net-imap-v0.4.18]: https://github.com/ruby/net-imap/releases/tag/v0.4.18
[net-imap-v0.5.1]: https://github.com/ruby/net-imap/releases/tag/v0.5.1
[net-imap-v0.5.2]: https://github.com/ruby/net-imap/releases/tag/v0.5.2
[net-imap-v0.5.3]: https://github.com/ruby/net-imap/releases/tag/v0.5.3
[net-imap-v0.5.4]: https://github.com/ruby/net-imap/releases/tag/v0.5.4
[net-smtp-v0.4.0.1]: https://github.com/ruby/net-smtp/releases/tag/v0.4.0.1
[net-smtp-v0.5.0]: https://github.com/ruby/net-smtp/releases/tag/v0.5.0
[prime-v0.1.3]: https://github.com/ruby/prime/releases/tag/v0.1.3
[rbs-v3.4.1]: https://github.com/ruby/rbs/releases/tag/v3.4.1
[rbs-v3.4.2]: https://github.com/ruby/rbs/releases/tag/v3.4.2
[rbs-v3.4.3]: https://github.com/ruby/rbs/releases/tag/v3.4.3
[rbs-v3.4.4]: https://github.com/ruby/rbs/releases/tag/v3.4.4
[rbs-v3.5.0.pre.1]: https://github.com/ruby/rbs/releases/tag/v3.5.0.pre.1
[rbs-v3.5.0.pre.2]: https://github.com/ruby/rbs/releases/tag/v3.5.0.pre.2
[rbs-v3.5.0]: https://github.com/ruby/rbs/releases/tag/v3.5.0
[rbs-v3.5.1]: https://github.com/ruby/rbs/releases/tag/v3.5.1
[rbs-v3.5.2]: https://github.com/ruby/rbs/releases/tag/v3.5.2
[rbs-v3.5.3]: https://github.com/ruby/rbs/releases/tag/v3.5.3
[rbs-v3.6.0.dev.1]: https://github.com/ruby/rbs/releases/tag/v3.6.0.dev.1
[rbs-v3.6.0.pre.1]: https://github.com/ruby/rbs/releases/tag/v3.6.0.pre.1
[rbs-v3.6.0.pre.2]: https://github.com/ruby/rbs/releases/tag/v3.6.0.pre.2
[rbs-v3.6.0.pre.3]: https://github.com/ruby/rbs/releases/tag/v3.6.0.pre.3
[rbs-v3.6.0]: https://github.com/ruby/rbs/releases/tag/v3.6.0
[rbs-v3.6.1]: https://github.com/ruby/rbs/releases/tag/v3.6.1
[rbs-v3.7.0.dev.1]: https://github.com/ruby/rbs/releases/tag/v3.7.0.dev.1
[rbs-v3.7.0.pre.1]: https://github.com/ruby/rbs/releases/tag/v3.7.0.pre.1
[rbs-v3.7.0]: https://github.com/ruby/rbs/releases/tag/v3.7.0
[rbs-v3.8.0.pre.1]: https://github.com/ruby/rbs/releases/tag/v3.8.0.pre.1
[rbs-v3.8.0]: https://github.com/ruby/rbs/releases/tag/v3.8.0
[debug-v1.9.2]: https://github.com/ruby/debug/releases/tag/v1.9.2
[debug-v1.10.0]: https://github.com/ruby/debug/releases/tag/v1.10.0
[racc-v1.8.0]: https://github.com/ruby/racc/releases/tag/v1.8.0
[racc-v1.8.1]: https://github.com/ruby/racc/releases/tag/v1.8.1
[mutex_m-v0.3.0]: https://github.com/ruby/mutex_m/releases/tag/v0.3.0
[bigdecimal-v3.1.6]: https://github.com/ruby/bigdecimal/releases/tag/v3.1.6
[bigdecimal-v3.1.7]: https://github.com/ruby/bigdecimal/releases/tag/v3.1.7
[bigdecimal-v3.1.8]: https://github.com/ruby/bigdecimal/releases/tag/v3.1.8
[drb-v2.2.1]: https://github.com/ruby/drb/releases/tag/v2.2.1
[nkf-v0.2.0]: https://github.com/ruby/nkf/releases/tag/v0.2.0
[syslog-v0.2.0]: https://github.com/ruby/syslog/releases/tag/v0.2.0
[csv-v3.2.9]: https://github.com/ruby/csv/releases/tag/v3.2.9
[csv-v3.3.0]: https://github.com/ruby/csv/releases/tag/v3.3.0
[csv-v3.3.1]: https://github.com/ruby/csv/releases/tag/v3.3.1
[csv-v3.3.2]: https://github.com/ruby/csv/releases/tag/v3.3.2
[ruby/net-http-sspi]: https://github.com/ruby/net-http-sspi
[typeprof-v0.30.1]: https://github.com/ruby/typeprof/releases/tag/v0.30.1

[RubyGems]: https://github.com/rubygems/rubygems
[benchmark]: https://github.com/ruby/benchmark
[bundler]: https://github.com/rubygems/rubygems
[date]: https://github.com/ruby/date
[delegate]: https://github.com/ruby/delegate
[did_you_mean]: https://github.com/ruby/did_you_mean
[digest]: https://github.com/ruby/digest
[erb]: https://github.com/ruby/erb
[error_highlight]: https://github.com/ruby/error_highlight
[etc]: https://github.com/ruby/etc
[fcntl]: https://github.com/ruby/fcntl
[fiddle]: https://github.com/ruby/fiddle
[fileutils]: https://github.com/ruby/fileutils
[io-console]: https://github.com/ruby/io-console
[io-nonblock]: https://github.com/ruby/io-nonblock
[ipaddr]: https://github.com/ruby/ipaddr
[irb]: https://github.com/ruby/irb
[json]: https://github.com/ruby/json
[logger]: https://github.com/ruby/logger
[net-http]: https://github.com/ruby/net-http
[open-uri]: https://github.com/ruby/open-uri
[optparse]: https://github.com/ruby/optparse
[ostruct]: https://github.com/ruby/ostruct
[pathname]: https://github.com/ruby/pathname
[pp]: https://github.com/ruby/pp
[prism]: https://github.com/ruby/prism
[pstore]: https://github.com/ruby/pstore
[psych]: https://github.com/ruby/psych
[rdoc]: https://github.com/ruby/rdoc
[reline]: https://github.com/ruby/reline
[resolv]: https://github.com/ruby/resolv
[securerandom]: https://github.com/ruby/securerandom
[set]: https://github.com/ruby/set
[shellwords]: https://github.com/ruby/shellwords
[singleton]: https://github.com/ruby/singleton
[stringio]: https://github.com/ruby/stringio
[strscan]: https://github.com/ruby/strscan
[syntax_suggest]: https://github.com/ruby/syntax_suggest
[tempfile]: https://github.com/ruby/tempfile
[time]: https://github.com/ruby/time
[timeout]: https://github.com/ruby/timeout
[tmpdir]: https://github.com/ruby/tmpdir
[uri]: https://github.com/ruby/uri
[win32ole]: https://github.com/ruby/win32ole
[yaml]: https://github.com/ruby/yaml
[zlib]: https://github.com/ruby/zlib

[repl_type_completor]: https://github.com/ruby/repl_type_completor
[minitest]: https://github.com/seattlerb/minitest
[power_assert]: https://github.com/ruby/power_assert
[rake]: https://github.com/ruby/rake
[test-unit]: https://github.com/test-unit/test-unit
[rexml]: https://github.com/ruby/rexml
[rss]: https://github.com/ruby/rss
[net-ftp]: https://github.com/ruby/net-ftp
[net-imap]: https://github.com/ruby/net-imap
[net-smtp]: https://github.com/ruby/net-smtp
[prime]: https://github.com/ruby/prime
[rbs]: https://github.com/ruby/rbs
[typeprof]: https://github.com/ruby/typeprof
[debug]: https://github.com/ruby/debug
[racc]: https://github.com/ruby/racc
[mutex_m]: https://github.com/ruby/mutex_m
[getoptlong]: https://github.com/ruby/getoptlong
[base64]: https://github.com/ruby/base64
[bigdecimal]: https://github.com/ruby/bigdecimal
[observer]: https://github.com/ruby/observer
[abbrev]: https://github.com/ruby/abbrev
[resolv-replace]: https://github.com/ruby/resolv-replace
[rinda]: https://github.com/ruby/rinda
[drb]: https://github.com/ruby/drb
[nkf]: https://github.com/ruby/nkf
[syslog]: https://github.com/ruby/syslog
[csv]: https://github.com/ruby/csv
