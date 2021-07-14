# NEWS for Ruby 3.0.0

This document is a list of user visible feature changes
since the **2.7.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* Keyword arguments are now separated from positional arguments.
  Code that resulted in deprecation warnings in Ruby 2.7 will now
  result in ArgumentError or different behavior. [[Feature #14183]]

* Procs accepting a single rest argument and keywords are no longer
  subject to autosplatting.  This now matches the behavior of Procs
  accepting a single rest argument and no keywords.
  [[Feature #16166]]

    ```ruby
    pr = proc{|*a, **kw| [a, kw]}

    pr.call([1])
    # 2.7 => [[1], {}]
    # 3.0 => [[[1]], {}]

    pr.call([1, {a: 1}])
    # 2.7 => [[1], {:a=>1}] # and deprecation warning
    # 3.0 => [[[1, {:a=>1}]], {}]
    ```

* Arguments forwarding (`...`) now supports leading arguments.
  [[Feature #16378]]

    ```ruby
    def method_missing(meth, ...)
      send(:"do_#{meth}", ...)
    end
    ```

* Pattern matching (`case/in`) is no longer experimental. [[Feature #17260]]

* One-line pattern matching is redesigned.  [EXPERIMENTAL]

    * `=>` is added. It can be used like a rightward assignment.
      [[Feature #17260]]

        ```ruby
        0 => a
        p a #=> 0

        {b: 0, c: 1} => {b:}
        p b #=> 0
        ```

    * `in` is changed to return `true` or `false`. [[Feature #17371]]

        ```ruby
        # version 3.0
        0 in 1 #=> false

        # version 2.7
        0 in 1 #=> raise NoMatchingPatternError
        ```

* Find-pattern is added.  [EXPERIMENTAL]
  [[Feature #16828]]

    ```ruby
    case ["a", 1, "b", "c", 2, "d", "e", "f", 3]
    in [*pre, String => x, String => y, *post]
      p pre  #=> ["a", 1]
      p x    #=> "b"
      p y    #=> "c"
      p post #=> [2, "d", "e", "f", 3]
    end
    ```

* Endless method definition is added.  [EXPERIMENTAL]
  [[Feature #16746]]

    ```ruby
    def square(x) = x * x
    ```

* Interpolated String literals are no longer frozen when
  `# frozen-string-literal: true` is used. [[Feature #17104]]

* Magic comment `shareable_constant_value` added to freeze constants.
  See {Magic Comments}[rdoc-ref:doc/syntax/comments.rdoc@Magic+Comments] for more details.
  [[Feature #17273]]

* A {static analysis}[rdoc-label:label-Static+analysis] foundation is
  introduced.
    * {RBS}[rdoc-label:label-RBS] is introduced. It is a type definition
      language for Ruby programs.
    * {TypeProf}[rdoc-label:label-TypeProf] is experimentally bundled. It is a
      type analysis tool for Ruby programs.

* Deprecation warnings are no longer shown by default (since Ruby 2.7.2).
  Turn them on with `-W:deprecated` (or with `-w` to show other warnings too).
  [[Feature #16345]]

* `$SAFE` and `$KCODE` are now normal global variables with no special behavior.
  C-API methods related to `$SAFE` have been removed.
  [[Feature #16131]] [[Feature #17136]]

* yield in singleton class definitions in methods is now a SyntaxError
  instead of a warning. yield in a class definition outside of a method
  is now a SyntaxError instead of a LocalJumpError.  [[Feature #15575]]

* When a class variable is overtaken by the same definition in an
  ancestor class/module, a RuntimeError is now raised (previously,
  it only issued a warning in verbose mode).  Additionally, accessing a
  class variable from the toplevel scope is now a RuntimeError.
  [[Bug #14541]]

* Assigning to a numbered parameter is now a SyntaxError instead of
  a warning.

## Command line options

### `--help` option

When the environment variable `RUBY_PAGER` or `PAGER` is present and has
a non-empty value, and the standard input and output are tty, the `--help`
option shows the help message via the pager designated by the value.
[[Feature #16754]]

### `--backtrace-limit` option

The `--backtrace-limit` option limits the maximum length of a backtrace.
[[Feature #8661]]

## Core classes updates

Outstanding ones only.

* Array

    * The following methods now return Array instances instead of
      subclass instances when called on subclass instances:
      [[Bug #6087]]

        * Array#drop
        * Array#drop_while
        * Array#flatten
        * Array#slice!
        * Array#slice / Array#[]
        * Array#take
        * Array#take_while
        * Array#uniq
        * Array#*

    * Can be sliced with Enumerator::ArithmeticSequence

        ```ruby
        dirty_data = ['--', 'data1', '--', 'data2', '--', 'data3']
        dirty_data[(1..).step(2)] # take each second element
        # => ["data1", "data2", "data3"]
        ```

* Binding

    * Binding#eval when called with one argument will use `"(eval)"`
      for `__FILE__` and `1` for `__LINE__` in the evaluated code.
      [[Bug #4352]] [[Bug #17419]]

* ConditionVariable

    * ConditionVariable#wait may now invoke the `block`/`unblock` scheduler
      hooks in a non-blocking context. [[Feature #16786]]

* Dir

    * Dir.glob and Dir.[] now sort the results by default, and
      accept the `sort:` keyword option.  [[Feature #8709]]

* ENV

    * ENV.except has been added, which returns a hash excluding the
      given keys and their values.  [[Feature #15822]]

    * Windows: Read ENV names and values as UTF-8 encoded Strings
      [[Feature #12650]]

* Encoding

    * Added new encoding IBM720.  [[Feature #16233]]

    * Changed default for Encoding.default_external to UTF-8 on Windows
      [[Feature #16604]]

* Fiber

    * Fiber.new(blocking: true/false) allows you to create non-blocking
      execution contexts. [[Feature #16786]]

    * Fiber#blocking? tells whether the fiber is non-blocking. [[Feature #16786]]

    * Fiber#backtrace and Fiber#backtrace_locations provide per-fiber backtrace.
      [[Feature #16815]]

    * The limitation of Fiber#transfer is relaxed. [[Bug #17221]]

* GC

    * GC.auto_compact= and GC.auto_compact have been added to control
      when compaction runs.  Setting `auto_compact=` to `true` will cause
      compaction to occur during major collections.  At the moment,
      compaction adds significant overhead to major collections, so please
      test first!  [[Feature #17176]]

* Hash

    * Hash#transform_keys and Hash#transform_keys! now accept a hash that maps
      keys to new keys.  [[Feature #16274]]

    * Hash#except has been added, which returns a hash excluding the
      given keys and their values.  [[Feature #15822]]

* IO

    * IO#nonblock? now defaults to `true`. [[Feature #16786]]

    * IO#wait_readable, IO#wait_writable, IO#read, IO#write and other
      related methods (e.g. IO#puts, IO#gets) may invoke the scheduler hook
      `#io_wait(io, events, timeout)` in a non-blocking execution context.
      [[Feature #16786]]

* Kernel

    * Kernel#clone when called with the `freeze: false` keyword will call
      `#initialize_clone` with the `freeze: false` keyword.
      [[Bug #14266]]

    * Kernel#clone when called with the `freeze: true` keyword will call
      `#initialize_clone` with the `freeze: true` keyword, and will
      return a frozen copy even if the receiver is unfrozen.
      [[Feature #16175]]

    * Kernel#eval when called with two arguments will use `"(eval)"`
      for `__FILE__` and `1` for `__LINE__` in the evaluated code.
      [[Bug #4352]]

    * Kernel#lambda now warns if called without a literal block.
      [[Feature #15973]]

    * Kernel.sleep invokes the scheduler hook `#kernel_sleep(...)` in a
      non-blocking execution context. [[Feature #16786]]

* Module

    * Module#include and Module#prepend now affect classes and modules
      that have already included or prepended the receiver, mirroring the
      behavior if the arguments were included in the receiver before
      the other modules and classes included or prepended the receiver.
      [[Feature #9573]]

        ```ruby
        class C; end
        module M1; end
        module M2; end
        C.include M1
        M1.include M2
        p C.ancestors #=> [C, M1, M2, Object, Kernel, BasicObject]
        ```

    * Module#public, Module#protected, Module#private, Module#public_class_method,
      Module#private_class_method, toplevel "private" and "public" methods
      now accept single array argument with a list of method names. [[Feature #17314]]

    * Module#attr_accessor, Module#attr_reader, Module#attr_writer and Module#attr
      methods now return an array of defined method names as symbols.
      [[Feature #17314]]

    * Module#alias_method now returns the defined alias as a symbol.
      [[Feature #17314]]

* Mutex

    * `Mutex` is now acquired per-`Fiber` instead of per-`Thread`. This change
      should be compatible for essentially all usages and avoids blocking when
      using a scheduler. [[Feature #16792]]

* Proc

    * Proc#== and Proc#eql? are now defined and will return true for
      separate Proc instances if the procs were created from the same block.
      [[Feature #14267]]

* Queue / SizedQueue

    * Queue#pop, SizedQueue#push and related methods may now invoke the
      `block`/`unblock` scheduler hooks in a non-blocking context.
      [[Feature #16786]]

* Ractor

    * New class added to enable parallel execution. See rdoc-ref:ractor.md for
      more details.

* Random

    * `Random::DEFAULT` now refers to the `Random` class instead of being a `Random` instance,
      so it can work with `Ractor`.
      [[Feature #17322]]

    * `Random::DEFAULT` is deprecated since its value is now confusing and it is no longer global,
      use `Kernel.rand`/`Random.rand` directly, or create a `Random` instance with `Random.new` instead.
      [[Feature #17351]]


* String

    * The following methods now return or yield String instances
      instead of subclass instances when called on subclass instances:
      [[Bug #10845]]

        * String#*
        * String#capitalize
        * String#center
        * String#chomp
        * String#chop
        * String#delete
        * String#delete_prefix
        * String#delete_suffix
        * String#downcase
        * String#dump
        * String#each_char
        * String#each_grapheme_cluster
        * String#each_line
        * String#gsub
        * String#ljust
        * String#lstrip
        * String#partition
        * String#reverse
        * String#rjust
        * String#rpartition
        * String#rstrip
        * String#scrub
        * String#slice!
        * String#slice / String#[]
        * String#split
        * String#squeeze
        * String#strip
        * String#sub
        * String#succ / String#next
        * String#swapcase
        * String#tr
        * String#tr_s
        * String#upcase

* Symbol

    * Symbol#to_proc now returns a lambda Proc.  [[Feature #16260]]

    * Symbol#name has been added, which returns the name of the symbol
      if it is named.  The returned string is frozen.  [[Feature #16150]]

* Fiber

    * Introduce Fiber.set_scheduler for intercepting blocking operations and
      Fiber.scheduler for accessing the current scheduler. See
      rdoc-ref:fiber.md for more details about what operations are supported and
      how to implement the scheduler hooks. [[Feature #16786]]

    * Fiber.blocking? tells whether the current execution context is
      blocking. [[Feature #16786]]

    * Thread#join invokes the scheduler hooks `block`/`unblock` in a
      non-blocking execution context. [[Feature #16786]]

* Thread

    * Thread.ignore_deadlock accessor has been added for disabling the
      default deadlock detection, allowing the use of signal handlers to
      break deadlock. [[Bug #13768]]

* Warning

    * Warning#warn now supports a category keyword argument.
      [[Feature #17122]]

## Stdlib updates

Outstanding ones only.

* BigDecimal

    * Update to BigDecimal 3.0.0

    * This version is Ractor compatible.

* Bundler

    * Update to Bundler 2.2.3

* CGI

    * Update to 0.2.0

    * This version is Ractor compatible.

* CSV

    * Update to CSV 3.1.9

* Date

    * Update to Date 3.1.1

    * This version is Ractor compatible.

* Digest

    * Update to Digest 3.0.0

    * This version is Ractor compatible.

* Etc

    * Update to Etc 1.2.0

    * This version is Ractor compatible.

* Fiddle

    * Update to Fiddle 1.0.5

* IRB

    * Update to IRB 1.2.6

* JSON

    * Update to JSON 2.5.0

    * This version is Ractor compatible.

* Set

    * Update to set 1.0.0

    * SortedSet has been removed for dependency and performance reasons.

    * Set#join is added as a shorthand for `.to_a.join`.

    * Set#<=> is added.

* Socket

    * Add :connect_timeout to TCPSocket.new [[Feature #17187]]

* Net::HTTP

    * Net::HTTP#verify_hostname= and Net::HTTP#verify_hostname have been
      added to skip hostname verification.  [[Feature #16555]]

    * Net::HTTP.get, Net::HTTP.get_response, and Net::HTTP.get_print
      can take the request headers as a Hash in the second argument when the
      first argument is a URI.  [[Feature #16686]]

* Net::SMTP

    * Add SNI support.

    * Net::SMTP.start arguments are keyword arguments.

    * TLS should not check the host name by default.

* OpenStruct

    * Initialization is no longer lazy. [[Bug #12136]]

    * Builtin methods can now be overridden safely. [[Bug #15409]]

    * Implementation uses only methods ending with `!`.

    * Ractor compatible.

    * Improved support for YAML. [[Bug #8382]]

    * Use officially discouraged. Read OpenStruct@Caveats section.

* Pathname

    * Ractor compatible.

* Psych

    * Update to Psych 3.3.0

    * This version is Ractor compatible.

* Reline

    * Update to Reline 0.1.5

* RubyGems

    * Update to RubyGems 3.2.3

* StringIO

    * Update to StringIO 3.0.0

    * This version is Ractor compatible.

* StringScanner

    * Update to StringScanner 3.0.0

    * This version is Ractor compatible.

## Compatibility issues

Excluding feature bug fixes.

* Regexp literals and all Range objects are frozen. [[Feature #8948]] [[Feature #16377]] [[Feature #15504]]

    ```ruby
    /foo/.frozen? #=> true
    (42...).frozen? # => true
    ```

* EXPERIMENTAL: Hash#each consistently yields a 2-element array. [[Bug #12706]]

    * Now `{ a: 1 }.each(&->(k, v) { })` raises an ArgumentError
      due to lambda's arity check.

* When writing to STDOUT redirected to a closed pipe, no broken pipe
  error message will be shown now.  [[Feature #14413]]

* `TRUE`/`FALSE`/`NIL` constants are no longer defined.

* Integer#zero? overrides Numeric#zero? for optimization.  [[Misc #16961]]

* Enumerable#grep and Enumerable#grep_v when passed a Regexp and no block no longer modify
  Regexp.last_match. [[Bug #17030]]

* Requiring 'open-uri' no longer redefines `Kernel#open`.
  Call `URI.open` directly or `use URI#open` instead. [[Misc #15893]]

* SortedSet has been removed for dependency and performance reasons.

## Stdlib compatibility issues

* Default gems

    * The following libraries are promoted to default gems from stdlib.

        * English
        * abbrev
        * base64
        * drb
        * debug
        * erb
        * find
        * net-ftp
        * net-http
        * net-imap
        * net-protocol
        * open-uri
        * optparse
        * pp
        * prettyprint
        * resolv-replace
        * resolv
        * rinda
        * set
        * securerandom
        * shellwords
        * tempfile
        * tmpdir
        * time
        * tsort
        * un
        * weakref

    * The following extensions are promoted to default gems from stdlib.

        * digest
        * io-nonblock
        * io-wait
        * nkf
        * pathname
        * syslog
        * win32ole

* Bundled gems

    * net-telnet and xmlrpc have been removed from the bundled gems.
      If you are interested in maintaining them, please comment on
      your plan to https://github.com/ruby/xmlrpc
      or https://github.com/ruby/net-telnet.

* SDBM has been removed from the Ruby standard library. [[Bug #8446]]

    * The issues of sdbm will be handled at https://github.com/ruby/sdbm

* WEBrick has been removed from the Ruby standard library. [[Feature #17303]]

    * The issues of WEBrick will be handled at https://github.com/ruby/webrick

## C API updates

* C API functions related to `$SAFE` have been removed.
  [[Feature #16131]]

* C API header file `ruby/ruby.h` was split. [[GH-2991]]

    This should have no impact on extension libraries,
    but users might experience slow compilations.

* Memory view interface [EXPERIMENTAL]

    * The memory view interface is a C-API set to exchange a raw memory area,
      such as a numeric array or a bitmap image, between extension libraries.
      The extension libraries can share also the metadata of the memory area
      that consists of the shape, the element format, and so on.
      Using these kinds of metadata, the extension libraries can share even
      a multidimensional array appropriately.
      This feature is designed by referring to Python's buffer protocol.
      [[Feature #13767]] [[Feature #14722]]

* Ractor related C APIs are introduced (experimental) in "include/ruby/ractor.h".

## Implementation improvements

* New method cache mechanism for Ractor. [[Feature #16614]]

    * Inline method caches pointed from ISeq can be accessed by multiple Ractors
      in parallel and synchronization is needed even for method caches. However,
      such synchronization can be overhead so introducing new inline method cache
      mechanisms, (1) Disposable inline method cache (2) per-Class method cache
      and (3) new invalidation mechanism. (1) can avoid per-method call
      synchronization because it only uses atomic operations.
      See the ticket for more details.

* The number of hashes allocated when using a keyword splat in
  a method call has been reduced to a maximum of 1, and passing
  a keyword splat to a method that accepts specific keywords
  does not allocate a hash.

* `super` is optimized when the same type of method is called in the previous call
  if it's not refinements or an attr reader or writer.

### JIT

* Performance improvements of JIT-ed code

    * Microarchitectural optimizations

        * Native functions shared by multiple methods are deduplicated on JIT compaction.

        * Decrease code size of hot paths by some optimizations and partitioning cold paths.

    * Instance variables

        * Eliminate some redundant checks.

        * Skip checking a class and a object multiple times in a method when possible.

        * Optimize accesses in some core classes like Hash and their subclasses.

    * Method inlining support for some C methods

        * `Kernel`: `#class`, `#frozen?`

        * `Integer`: `#-@`, `#~`, `#abs`, `#bit_length`, `#even?`, `#integer?`, `#magnitude`,
          `#odd?`, `#ord`, `#to_i`, `#to_int`, `#zero?`

        * `Struct`: reader methods for 10th or later members

    * Constant references are inlined.

    * Always generate appropriate code for `==`, `nil?`, and `!` calls depending on
      a receiver class.

    * Reduce the number of PC accesses on branches and method returns.

    * Optimize C method calls a little.

* Compilation process improvements

    * It does not keep temporary files in /tmp anymore.

    * Throttle GC and compaction of JIT-ed code.

    * Avoid GC-ing JIT-ed code when not necessary.

    * GC-ing JIT-ed code is executed in a background thread.

    * Reduce the number of locks between Ruby and JIT threads.

## Static analysis

### RBS

* RBS is a new language for type definition of Ruby programs.
  It allows writing types of classes and modules with advanced
  types including union types, overloading, generics, and
  _interface types_ for duck typing.

* Ruby ships with type definitions for core/stdlib classes.

* `rbs` gem is bundled to load and process RBS files.

### TypeProf

* TypeProf is a type analysis tool for Ruby code based on abstract interpretation.

    * It reads non-annotated Ruby code, tries inferring its type signature, and prints
      the analysis result in RBS format.

    * Though it supports only a subset of the Ruby language yet, we will continuously
      improve the coverage of language features, analysis performance, and usability.

```ruby
# test.rb
def foo(x)
  if x > 10
    x.to_s
  else
    nil
  end
end

foo(42)
```

```
$ typeprof test.rb
# Classes
class Object
  def foo : (Integer) -> String?
end
```

## Miscellaneous changes

* Methods using `ruby2_keywords` will no longer keep empty keyword
  splats, those are now removed just as they are for methods not
  using `ruby2_keywords`.

* When an exception is caught in the default handler, the error
  message and backtrace are printed in order from the innermost.
  [[Feature #8661]]

* Accessing an uninitialized instance variable no longer emits a
  warning in verbose mode. [[Feature #17055]]

[Bug #4352]:      https://bugs.ruby-lang.org/issues/4352
[Bug #6087]:      https://bugs.ruby-lang.org/issues/6087
[Bug #8382]:      https://bugs.ruby-lang.org/issues/8382
[Bug #8446]:      https://bugs.ruby-lang.org/issues/8446
[Feature #8661]:  https://bugs.ruby-lang.org/issues/8661
[Feature #8709]:  https://bugs.ruby-lang.org/issues/8709
[Feature #8948]:  https://bugs.ruby-lang.org/issues/8948
[Feature #9573]:  https://bugs.ruby-lang.org/issues/9573
[Bug #10845]:     https://bugs.ruby-lang.org/issues/10845
[Bug #12136]:     https://bugs.ruby-lang.org/issues/12136
[Feature #12650]: https://bugs.ruby-lang.org/issues/12650
[Bug #12706]:     https://bugs.ruby-lang.org/issues/12706
[Feature #13767]: https://bugs.ruby-lang.org/issues/13767
[Bug #13768]:     https://bugs.ruby-lang.org/issues/13768
[Feature #14183]: https://bugs.ruby-lang.org/issues/14183
[Bug #14266]:     https://bugs.ruby-lang.org/issues/14266
[Feature #14267]: https://bugs.ruby-lang.org/issues/14267
[Feature #14413]: https://bugs.ruby-lang.org/issues/14413
[Bug #14541]:     https://bugs.ruby-lang.org/issues/14541
[Feature #14722]: https://bugs.ruby-lang.org/issues/14722
[Bug #15409]:     https://bugs.ruby-lang.org/issues/15409
[Feature #15504]: https://bugs.ruby-lang.org/issues/15504
[Feature #15575]: https://bugs.ruby-lang.org/issues/15575
[Feature #15822]: https://bugs.ruby-lang.org/issues/15822
[Misc #15893]:    https://bugs.ruby-lang.org/issues/15893
[Feature #15921]: https://bugs.ruby-lang.org/issues/15921
[Feature #15973]: https://bugs.ruby-lang.org/issues/15973
[Feature #16131]: https://bugs.ruby-lang.org/issues/16131
[Feature #16150]: https://bugs.ruby-lang.org/issues/16150
[Feature #16166]: https://bugs.ruby-lang.org/issues/16166
[Feature #16175]: https://bugs.ruby-lang.org/issues/16175
[Feature #16233]: https://bugs.ruby-lang.org/issues/16233
[Feature #16260]: https://bugs.ruby-lang.org/issues/16260
[Feature #16274]: https://bugs.ruby-lang.org/issues/16274
[Feature #16345]: https://bugs.ruby-lang.org/issues/16345
[Feature #16377]: https://bugs.ruby-lang.org/issues/16377
[Feature #16378]: https://bugs.ruby-lang.org/issues/16378
[Feature #16555]: https://bugs.ruby-lang.org/issues/16555
[Feature #16604]: https://bugs.ruby-lang.org/issues/16604
[Feature #16614]: https://bugs.ruby-lang.org/issues/16614
[Feature #16686]: https://bugs.ruby-lang.org/issues/16686
[Feature #16746]: https://bugs.ruby-lang.org/issues/16746
[Feature #16754]: https://bugs.ruby-lang.org/issues/16754
[Feature #16786]: https://bugs.ruby-lang.org/issues/16786
[Feature #16792]: https://bugs.ruby-lang.org/issues/16792
[Feature #16815]: https://bugs.ruby-lang.org/issues/16815
[Feature #16828]: https://bugs.ruby-lang.org/issues/16828
[Misc #16961]:    https://bugs.ruby-lang.org/issues/16961
[Bug #17030]:     https://bugs.ruby-lang.org/issues/17030
[Feature #17055]: https://bugs.ruby-lang.org/issues/17055
[Feature #17104]: https://bugs.ruby-lang.org/issues/17104
[Feature #17122]: https://bugs.ruby-lang.org/issues/17122
[Feature #17136]: https://bugs.ruby-lang.org/issues/17136
[Feature #17176]: https://bugs.ruby-lang.org/issues/17176
[Feature #17187]: https://bugs.ruby-lang.org/issues/17187
[Bug #17221]:     https://bugs.ruby-lang.org/issues/17221
[Feature #17260]: https://bugs.ruby-lang.org/issues/17260
[Feature #17273]: https://bugs.ruby-lang.org/issues/17273
[Feature #17303]: https://bugs.ruby-lang.org/issues/17303
[Feature #17314]: https://bugs.ruby-lang.org/issues/17314
[Feature #17322]: https://bugs.ruby-lang.org/issues/17322
[Feature #17351]: https://bugs.ruby-lang.org/issues/17351
[Feature #17371]: https://bugs.ruby-lang.org/issues/17371
[Bug #17419]:     https://bugs.ruby-lang.org/issues/17419
[GH-2991]:        https://github.com/ruby/ruby/pull/2991
