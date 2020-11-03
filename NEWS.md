# NEWS for Ruby 3.0.0

This document is a list of user visible feature changes
since the **2.7.0** release, except for bug fixes.

Note that each entry is kept so brief that no reason behind or reference
information is supplied with.  For a full list of changes with all
sufficient information, see the ChangeLog file or Redmine
(e.g. `https://bugs.ruby-lang.org/issues/$FEATURE_OR_BUG_NUMBER`).

## Language changes

* Keyword arguments are now separated from positional arguments.
  Code that resulted in deprecation warnings in Ruby 2.7 will now
  result in ArgumentError or different behavior. [[Feature #14183]]

* Arguments forwarding (`...`) now supports leading arguments.
  [[Feature #16378]]

    ```ruby
    def method_missing(meth, ...)
      send(:"do_#{meth}", ...)
    end
    ```

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

* $SAFE is now a normal global variable with no special behavior.
  C-API methods related to $SAFE have been removed.
  [[Feature #16131]]

* yield in singleton class definitions in methods is now a SyntaxError
  instead of a warning. yield in a class definition outside of a method
  is now a SyntaxError instead of a LocalJumpError.  [[Feature #15575]]

* Pattern matching is no longer experimental. [[Feature #17260]]

* One-line pattern matching now uses `=>` instead of `in`.  [EXPERIMENTAL]
  [[Feature #17260]]

    ```ruby
    # version 3.0
    {a: 0, b: 1} => {a:}
    p a # => 0
    
    # version 2.7
    {a: 0, b: 1} in {a:}
    p a # => 0
    ```

* Find pattern is added.  [EXPERIMENTAL]
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

* When a class variable is overtaken by the same definition in an
  ancestor class/module, a RuntimeError is now raised (previously,
  it only issued a warning in verbose mode.  Additionally, accessing a
  class variable from the toplevel scope is now a RuntimeError.
  [[Bug #14541]]

* Rightward assignment statement is added.  [EXPERIMENTAL]
  [[Feature #15921]]

    ```ruby
    fib(10) => x
    ```

* Endless method definition is added.  [EXPERIMENTAL]
  [[Feature #16746]]

    ```ruby
    def square(x) = x * x
    ```

* Interpolated String literals are no longer frozen when
  `# frozen-string-literal: true` is used. [[Feature #17104]]

* A static analysis foundation is introduced.  See "Static analysis" section in detail.
  * RBS is introduced. It is a type definition language for Ruby programs.
  * TypeProf is experimentally bundled. It is a type analysis tool for Ruby programs.

## Command line options

### `--help` option

When the environment variable `RUBY_PAGER` or `PAGER` is present and has
non-empty value, and the standard input and output are tty, `--help`
option shows the help message via the pager designated by the value.
[[Feature #16754]]

## Core classes updates

Outstanding ones only.

* Dir

    * Modified method

        * Dir.glob and Dir.[] now sort the results by default, and
          accept `sort:` keyword option.  [[Feature #8709]]

* ENV

    * New method

        * ENV.except, which returns a hash excluding the given keys
          and their values.  [[Feature #15822]]

* Hash

    * Modified method

        * Hash#transform_keys now accepts a hash that maps keys to new
          keys.  [[Feature #16274]]

    * New method

        * Hash#except, which returns a hash excluding the given keys
          and their values.  [[Feature #15822]]

* Kernel

    * Modified method

        * Kernel#clone when called with `freeze: false` keyword will call
          `#initialize_clone` with the `freeze: false` keyword.
          [[Bug #14266]]

        * Kernel#clone when called with `freeze: true` keyword will call
          `#initialize_clone` with the `freeze: true` keyword, and will
          return a frozen copy even if the receiver is unfrozen.
          [[Feature #16175]]

        * Kernel#eval when called with two arguments will use "(eval)"
          for `__FILE__` and 1 for `__LINE__` in the evaluated code.
          [[Bug #4352]]

        * Kernel#lambda now warns if called without a literal block.
          [[Feature #15973]]

* Module

    * Modified method

        * Module#include and #prepend now affect classes and modules that
          have already included or prepended the receiver, mirroring the
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

* Range

    * All Range objects are frozen. [Feature #15504]

* Thread

    * Introduce `Thread#scheduler` for intercepting blocking operations and
      `Thread.scheduler` for accessing the current scheduler. See
      doc/scheduler.md for more details. [[Feature #16786]]
    * `Thread#blocking?` tells whether the current execution context is
      blocking. [[Feature #16786]]
    * `Thread#join` invokes the scheduler hooks `block`/`unblock` in a
      non-blocking execution context. [[Feature #16786]]
    * `Thread.ignore_deadlock` accessor for disabling the default deadlock
      detection, allowing the use of signal handlers to break deadlock.
      [[Bug #13768]]

* Mutex

    * `Mutex` is now acquired per-`Fiber` instead of per-`Thread`. This change
      should be compatible for essentially all usages and avoids blocking when
      using a scheduler. [[Feature #16792]]

* Fiber

    * `Fiber.new(blocking: true/false)` allows you to create non-blocking
      execution contexts. [[Feature #16786]]
    * `Fiber#blocking?` tells whether the fiber is non-blocking. [[Feature #16786]]
    * `Fiber#backtrace` & `Fiber#backtrace_locations` provide per-fiber backtrace.
      [[Feature #16815]]
    * The limitation of `Fiber#transfer` is relaxed. [Bug #17221]

* Kernel

    * `Kernel.sleep(...)` invokes the scheduler hook `#kernel_sleep(...)` in a
      non-blocking execution context. [[Feature #16786]]

* IO

    * `IO#nonblock?` now defaults to `true`. [[Feature #16786]]
    * `IO#wait_readable`, `IO#wait_writable`, `IO#read`, `IO#write` and other
      related methods (e.g. `#puts`, `#gets`) may invoke the scheduler hook
      `#io_wait(io, events, timeout)` in a non-blocking execution context.
      [[Feature #16786]]

* ConditionVariable

    * `ConditionVariable#wait` may now invoke the `block`/`unblock` scheduler
      hooks in a non-blocking context. [[Feature #16786]]

* Queue / SizedQueue

    * `Queue#pop`, `SizedQueue#push` and related methods may now invoke the
      `block`/`unblock` scheduler hooks in a non-blocking context.
      [[Feature #16786]]

* Ractor

    * new class to enable parallel execution. See doc/ractor.md for
      more details.

* Symbol

    * Modified method

        * Symbol#to_proc now returns a lambda Proc.
          [[Feature #16260]]

    * New method

        * Symbol#name, which returns the name of the symbol if it is
          named.  The returned string cannot be modified.
          [[Feature #16150]]

* Warning

    * Modified method

        * Warning#warn now supports a category kwarg.
        [[Feature #17122]]

* GC
    * New method

        * `GC.auto_compact=`, `GC.auto_compact` can be used to control when
          compaction runs.  Setting `auto_compact=` to true will cause
          compaction to occurr during major collections.  At the moment,
          compaction adds significant overhead to major collections, so please
          test first!
          [[Feature #17176]]

## Stdlib updates

Outstanding ones only.

* RubyGems

    * Update to RubyGems 3.2.0.rc.1

* Bundler

    * Update to Bundler 2.2.0.rc.1

* Net::HTTP

    * New method

        * Add Net::HTTP#verify_hostname= and Net::HTTP#verify_hostname
          to skip hostname verification.  [[Feature #16555]]

    * Modified method

        * Net::HTTP.get, Net::HTTP.get_response, and Net::HTTP.get_print can
          take request headers as a Hash in the second argument when the first
          argument is a URI.  [[Feature #16686]]

* IRB

    * Update to IRB 1.2.6

* OpenStruct

    * Initialization no longer lazy [[Bug #12136]]
    * Builtin methods can now be overridden safely. [[Bug #15409]]
    * Implementation uses only methods ending with `!`.
    * Ractor compatible.
    * Improved support for YAML [[Bug #8382]]
    * Use officially discouraged. Read "Caveats" section.

* Reline

    * Update to Reline 0.1.5

* Socket

    * TCPSocket.new now supports `resolv_timeout`. [[Feature #17134]]

      ```ruby
      # it raises SocketError if name resolution is not finished within resolve_timeout.
      tcp_socket = TCPSocket.new("example.com", 80, resolv_timeout: 10)
      ```

## Compatibility issues

Excluding feature bug fixes.

* Regexp literals are frozen [[Feature #8948]] [[Feature #16377]]

    ```ruby
    /foo/.frozen? #=> true
    ```

* EXPERIMENTAL: Hash#each consistently yields a 2-element array [[Bug #12706]]

    * Now `{ a: 1 }.each(&->(k, v) { })` raises an ArgumentError
      due to lambda's arity check.
    * This is experimental; if it brings a big incompatibility issue,
      it may be reverted until 2.8/3.0 release.

* When writing to STDOUT redirected to a closed pipe, no broken pipe
  error message will be shown now.  [[Feature #14413]]

* `TRUE`/`FALSE`/`NIL` constants are no longer defined.

* `Integer#zero?` overrides `Numeric#zero?` for optimization.  [[Misc #16961]]

## Stdlib compatibility issues

* Default gems

    * The following libraries are promoted the default gems from stdlib.

        * abbrev
        * base64
        * English
        * erb
        * find
        * io-nonblock
        * io-wait
        * net-ftp
        * net-http
        * net-imap
        * net-protocol
        * nkf
        * open-uri
        * optparse
        * resolv
        * resolv-replace
        * rinda
        * securerandom
        * set
        * shellwords
        * tempfile
        * time
        * tmpdir
        * tsort
        * weakref

* Bundled gems

    * net-telnet and xmlrpc have been removed from the bundled gems.
      If you are interested in maintaining them, please comment on
      your plan to https://github.com/ruby/xmlrpc
      or https://github.com/ruby/net-telnet.

* SDBM have been removed from ruby standard library. [[Bug #8446]]

    * The issues of sdbm will be handled at https://github.com/ruby/sdbm

## C API updates

* C API functions related to $SAFE have been removed.
  [[Feature #16131]]

* C API header file `ruby/ruby.h` was split. [[GH-2991]] Should have no impact
  on extension libraries, but users might experience slow compilations.

* Memory view interface [EXPERIMENTAL]

  * The memory view interface is a C-API set to exchange a raw memory area,
    such as a numeric array and a bitmap image, between extension libraries.
    The extension libraries can share also the metadata of the memory area
    that consists of the shape, the element format, and so on.
    Using these kinds of metadata, the extension libraries can share even
    a multidimensional array appropriately.
    This feature is designed by referring to Python's buffer protocol.
    [[Feature #13767]] [[Feature #14722]]

## Implementation improvements

* New method cache mechanism for Ractor [[Feature #16614]]

  * Inline method caches pointed from ISeq can be accessed by multiple Ractors
    in parallel and synchronization is needed even for method caches. However,
    such synchronization can be overhead so introducing new inline method cache
    mehanisms, (1) Disposable inline method cache (2) per-Class method cache
    and (3) new invalidation mechanism. (1) can avoid per-method call
    syncrhonization because it only use atomic operations.
    See the ticket for more details.

* The number of hashes allocated when using a keyword splat in
  a method call has been reduced to a maximum of 1, and passing
  a keyword splat to a method that accepts specific keywords
  does not allocate a hash.

* `super` is optimized when the same type of method is called in the previous call
  if it's not refinements or an attr reader or writer.

### JIT

* Native functions shared by multiple methods are deduplicated on JIT compaction.

* Decrease code size of hot paths by some optimizations and partitioning cold paths.

* Not only pure Ruby methods but also some C methods skip pushing a method frame.

  * `Kernel#class`, `Integer#zero?`

* Always generate appropriate code for `==`, `nil?`, and `!` calls depending on
  a receiver class.

* Optimize instance variable access in some core classes like Hash and their subclasses

* Eliminate VM register access on a method return

* Optimize C method call a little

## Statis analysis

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
    improve the coverage of language features, the analysis performance, and usability.

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

* Taint deprecation warnings are now issued in regular mode in
  addition to verbose warning mode.  [[Feature #16131]]

* When an exception is caught in the default handler, the error
  message and backtrace are printed in order from the innermost.
  [[Feature #8661]]


[Bug #4352]:      https://bugs.ruby-lang.org/issues/4352
[Bug #8382]:      https://bugs.ruby-lang.org/issues/8382
[Bug #8446]:      https://bugs.ruby-lang.org/issues/8446
[Feature #8661]:  https://bugs.ruby-lang.org/issues/8661
[Feature #8709]:  https://bugs.ruby-lang.org/issues/8709
[Feature #8948]:  https://bugs.ruby-lang.org/issues/8948
[Feature #9573]:  https://bugs.ruby-lang.org/issues/9573
[Bug #12136]:     https://bugs.ruby-lang.org/issues/12136
[Bug #12706]:     https://bugs.ruby-lang.org/issues/12706
[Feature #13767]: https://bugs.ruby-lang.org/issues/13767
[Feature #14183]: https://bugs.ruby-lang.org/issues/14183
[Bug #14266]:     https://bugs.ruby-lang.org/issues/14266
[Feature #14413]: https://bugs.ruby-lang.org/issues/14413
[Bug #14541]:     https://bugs.ruby-lang.org/issues/14541
[Feature #14722]: https://bugs.ruby-lang.org/issues/14722
[Bug #15409]:     https://bugs.ruby-lang.org/issues/15409
[Feature #15575]: https://bugs.ruby-lang.org/issues/15575
[Feature #15822]: https://bugs.ruby-lang.org/issues/15822
[Feature #15921]: https://bugs.ruby-lang.org/issues/15921
[Feature #15973]: https://bugs.ruby-lang.org/issues/15973
[Feature #16131]: https://bugs.ruby-lang.org/issues/16131
[Feature #16150]: https://bugs.ruby-lang.org/issues/16150
[Feature #16166]: https://bugs.ruby-lang.org/issues/16166
[Feature #16175]: https://bugs.ruby-lang.org/issues/16175
[Feature #16260]: https://bugs.ruby-lang.org/issues/16260
[Feature #16274]: https://bugs.ruby-lang.org/issues/16274
[Feature #16377]: https://bugs.ruby-lang.org/issues/16377
[Feature #16378]: https://bugs.ruby-lang.org/issues/16378
[Feature #16555]: https://bugs.ruby-lang.org/issues/16555
[Feature #16614]: https://bugs.ruby-lang.org/issues/16614
[Feature #16686]: https://bugs.ruby-lang.org/issues/16686
[Feature #16746]: https://bugs.ruby-lang.org/issues/16746
[Feature #16754]: https://bugs.ruby-lang.org/issues/16754
[Feature #16786]: https://bugs.ruby-lang.org/issues/16786
[Feature #16792]: https://bugs.ruby-lang.org/issues/16792
[Feature #16815]: https://bugs.ruby-lang.org/issues/16815
[Feature #16828]: https://bugs.ruby-lang.org/issues/16828
[Misc #16961]:    https://bugs.ruby-lang.org/issues/16961
[Feature #17104]: https://bugs.ruby-lang.org/issues/17104
[Feature #17122]: https://bugs.ruby-lang.org/issues/17122
[Feature #17134]: https://bugs.ruby-lang.org/issues/17134
[GH-2991]:        https://github.com/ruby/ruby/pull/2991
