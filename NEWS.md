# NEWS for Ruby 3.4.0

This document is a list of user-visible feature changes
since the **3.3.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* String literals in files without a `frozen_string_literal` comment now emit a deprecation warning
  when they are mutated.
  These warnings can be enabled with `-W:deprecated` or by setting `Warning[:deprecated] = true`.
  To disable this change, you can run Ruby with the `--disable-frozen-string-literal`
  command line argument. [[Feature #20205]]

    * String#+@ now duplicates when mutating the string would emit
      a deprecation warning, offered as a replacement for the
      `str.dup if str.frozen?` pattern.

* `it` is added to reference a block parameter. [[Feature #18980]]

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

    * Array#fetch_values was added. [[Feature #20702]]

* Exception

    * Exception#set_backtrace now accepts arrays of Thread::Backtrace::Location.
      Kernel#raise, Thread#raise and Fiber#raise also accept this new format. [[Feature #13557]]

* Fiber::Scheduler

    * An optional Fiber::Scheduler#blocking_operation_wait hook allows blocking operations to be moved out of the
      event loop in order to reduce latency and improve multi-core processor utilization. [[Feature #20876]]

* GC

    * GC.config added to allow setting configuration variables on the Garbage
      Collector. [[Feature #20443]]

    * GC configuration parameter `rgengc_allow_full_mark` introduced.  When `false`
      GC will only mark young objects. Default is `true`.  [[Feature #20443]]

* Hash

    * Hash.new now accepts an optional `capacity:` argument, to preallocate the hash with a given capacity.
      This can improve performance when building large hashes incrementally by saving on reallocation and
      rehashing of keys. [[Feature #19236]]

* IO::Buffer

    * IO::Buffer#copy can release the GVL, allowing other threads to run while copying data. [[Feature #20902]]

* Integer

    * Integer#** used to return `Float::INFINITY` when the return value is large, but now returns an Integer.
      If the return value is extremely large, it raises an exception.
      [[Feature #20811]]

* MatchData

    * MatchData#bytebegin and MatchData#byteend have been added. [[Feature #20576]]

* Ractor

    * `require` in Ractor is allowed. The requiring process will be run on
      the main Ractor.
      `Ractor._require(feature)` is added to run requiring process on the
      main Ractor.
      [[Feature #20627]]

    * Ractor.main? is added. [[Feature #20627]]

    * Ractor.[] and Ractor.[]= are added to access the ractor local storage
      of the current Ractor. [[Feature #20715]]

    * `Ractor.store_if_absent(key){ init }` is added to initialize ractor local
      variables in thread-safty. [[Feature #20875]]

* Range

    * Range#size now raises TypeError if the range is not iterable. [[Misc #18984]]
    * Range#step now consistently has a semantics of iterating by using `+` operator
      for all types, not only numerics. [[Feature #18368]]

        ```ruby
        (Time.utc(2022, 2, 24)..).step(24*60*60).take(3)
        #=> [2022-02-24 00:00:00 UTC, 2022-02-25 00:00:00 UTC, 2022-02-26 00:00:00 UTC]
        ```

* Rational

    * Rational#** used to return `Float::INFINITY` or `Float::NAN`
      when the numerator of the return value is large, but now returns an Integer.
      If it is extremely large, it raises an exception. [[Feature #20811]]

* RubyVM::AbstractSyntaxTree

    * Add RubyVM::AbstractSyntaxTree::Node#locations method which returns location objects
      associated with the AST node. [[Feature #20624]]
    * Add RubyVM::AbstractSyntaxTree::Location class which holds location information. [[Feature #20624]]


* String

    * String#append_as_bytes was added to more easily and efficiently work with binary buffers and protocols.
      It directly concatenate the arguments into the string without any encoding validation or conversion.
      [[Feature #20594]]

* Symbol

    * The string returned by Symbol#to_s now emits a deprecation warning when mutated, and will be
      frozen in a future version of Ruby.
      These warnings can be enabled with `-W:deprecated` or by setting `Warning[:deprecated] = true`.
      [[Feature #20350]]

* Time

    * On Windows, now Time#zone encodes the system timezone name in UTF-8
      instead of the active code page, if it contains non-ASCII characters.
      [[Bug #20929]]

    * Time#xmlschema, and its Time#iso8601 alias have been moved into the core Time
      class while previously it was an extension provided by the `time` gem. [[Feature #20707]]

* Warning

    * Add Warning.categories method which returns a list of possible warning categories.
      [[Feature #20293]]

## Stdlib updates

* RubyGems
    * Add --attestation option to gem push. It enabled to store signature of build artifact to sigstore.dev.

* Bundler
    * Add a lockfile_checksums configuration to include checksums in fresh lockfiles.
    * Add bundle lock --add-checksums to add checksums to an existing lockfile.

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

The following default gem is added.

* win32-registry 0.1.0

The following default gems are updated.

* RubyGems 3.6.0
* benchmark 0.4.0
* bundler 2.6.0
* date 3.4.1
* delegate 0.4.0
* did_you_mean 2.0.0
* digest 3.2.0
* erb 4.0.4
* error_highlight 0.7.0
* etc 1.4.5
* fcntl 1.2.0
* fiddle 1.1.6
* fileutils 1.7.3
* io-console 0.8.0
* io-nonblock 0.3.1
* ipaddr 1.2.7
* irb 1.14.2
* json 2.9.0
* logger 1.6.3
* net-http 0.6.0
* open-uri 0.5.0
* optparse 0.6.0
* ostruct 0.6.1
* pathname 0.4.0
* pp 0.6.2
* prism 1.2.0
* pstore 0.1.4
* psych 5.2.1
* rdoc 6.9.1
* reline 0.6.0
* resolv 0.6.0
* securerandom 0.4.1
* set 1.1.1
* shellwords 0.2.2
* singleton 0.3.0
* stringio 3.1.2
* strscan 3.1.2
* syntax_suggest 2.0.2
* tempfile 0.3.1
* time 0.4.1
* timeout 0.4.3
* tmpdir 0.3.1
* uri 1.0.2
* win32ole 1.9.1
* yaml 0.4.0
* zlib 3.2.1

The following bundled gem is added.

* repl_type_completor 0.1.9

The following bundled gems are updated.

* minitest 5.25.4
* power_assert 2.0.4
* rake 13.2.1
* test-unit 3.6.7
* rexml 3.4.0
* rss 0.3.1
* net-ftp 0.3.8
* net-imap 0.5.2
* net-smtp 0.5.0
* prime 0.1.3
* rbs 3.7.0
* typeprof 0.30.0
* debug 1.9.2
* racc 1.8.1

The following bundled gems are promoted from default gems.

* mutex_m 0.3.0
* getoptlong 0.2.1
* base64 0.2.0
* bigdecimal 3.1.8
* observer 0.1.2
* abbrev 0.1.2
* resolv-replace 0.1.1
* rinda 0.2.0
* drb 2.2.1
* nkf 0.2.0
* syslog 0.2.0
* csv 3.3.1

See GitHub releases like [GitHub Releases of Logger] or changelog for
details of the default gems or bundled gems.

[ruby/net-http-sspi]: https://github.com/ruby/net-http-sspi
[GitHub Releases of Logger]: https://github.com/ruby/logger/releases

## Supported platforms

## Compatibility issues

* Error messages and backtrace displays have been changed.

    * Use a single quote instead of a backtick as an opening quote. [[Feature #16495]]
    * Display a class name before a method name (only when the class has a permanent name). [[Feature #19117]]
    * Extra `rescue`/`ensure` frames are no longer available on the backtrace. [[Feature #20275]]
    * Kernel#caller, Thread::Backtrace::Location’s methods, etc. are also changed accordingly.

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

* Hash#inspect rendering have been changed. [[Bug #20433]]

    * Symbol keys are displayed using the modern symbol key syntax: `"{user: 1}"`
    * Other keys now have spaces around `=>`: `'{"user" => 1}'`, while previously they didn't: `'{"user"=>1}'`

* Kernel#Float() now accepts a decimal string with decimal part omitted. [[Feature #20705]]

  ```rb
  Float("1.")    #=> 1.0 (previously, an ArgumentError was raised)
  Float("1.E-1") #=> 0.1 (previously, an ArgumentError was raised)
  ```

* String#to_f now accepts a decimal string with decimal part omitted. [[Feature #20705]]
  Note that the result changes when an exponent is specified.

  ```rb
  "1.".to_f    #=> 1.0
  "1.E-1".to_f #=> 0.1 (previously, 1.0 was returned)
  ```

* Object#singleton_method now returns methods in modules prepended to or included in the
  receiver's singleton class. [[Bug #20620]]

  ```rb
  o = Object.new
  o.extend(Module.new{def a = 1})
  o.singleton_method(:a).call #=> 1
  ```

* Refinement#refined_class has been removed. [[Feature #19714]]

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

    * Reject negative values for Timeout.timeout. [[Bug #20795]]

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
  by attempting IPv6 and IPv4 concurrently, is used in Socket.tcp and TCPSocket.new.
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

* New features of YJIT
  * Add unified memory limit via `--yjit-mem-size` command-line option (default 128MiB)
    which tracks total YJIT memory usage and is more intuitive than the
    old `--yjit-exec-mem-size`.
  * More statistics now always available via `RubyVM::YJIT.runtime_stats`
  * Add compilation log to track what gets compiled via `--yjit-log`
    * Tail of the log also available at run-time via `RubyVM::YJIT.log`
  * Add support for shareable consts in multi-ractor mode
  * Can now trace counted exits with `--yjit-trace-exits=COUNTER`
  * Compressed context reduces memory needed to store YJIT metadata

* New optimizations of YJIT
  * Improved allocator with ability to allocate registers for local variables
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
  * Various other incremental optimizations

## Miscellaneous changes

* Passing a block to a method which doesn't use the passed block will show
  a warning on verbose mode (`-w`).
  In connection with this, a new `strict_unused_block` warning category was introduced.
  Turn them on with `-W:strict_unused_block` or `Warning[:strict_unused_block] = true`.
  [[Feature #15554]]

* Redefining some core methods that are specially optimized by the interpreter
  and JIT like String#freeze or Integer#+ now emits a performance class
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
[Feature #20782]: https://bugs.ruby-lang.org/issues/20782
[Bug #20795]:     https://bugs.ruby-lang.org/issues/20795
[Feature #20811]: https://bugs.ruby-lang.org/issues/20811
[Feature #20860]: https://bugs.ruby-lang.org/issues/20860
[Feature #20875]: https://bugs.ruby-lang.org/issues/20875
[Feature #20876]: https://bugs.ruby-lang.org/issues/20876
[Feature #20884]: https://bugs.ruby-lang.org/issues/20884
[Feature #20902]: https://bugs.ruby-lang.org/issues/20902
[Bug #20929]:     https://bugs.ruby-lang.org/issues/20929
