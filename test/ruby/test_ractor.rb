# frozen_string_literal: false
require 'test/unit'

class TestRactor < Test::Unit::TestCase
  def test_shareability_of_iseq_proc
    assert_raise Ractor::IsolationError do
      foo = []
      Ractor.shareable_proc{ foo }
    end
  end

  def test_shareability_of_method_proc
    # TODO: fix with Ractor.shareable_proc/lambda
=begin
    str = +""

    x = str.instance_exec { proc { to_s } }
    assert_unshareable(x, /Proc\'s self is not shareable/)

    x = str.instance_exec { method(:to_s) }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:to_s).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:itself).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String(Kernel)#itself()>", exception: Ractor::Error)

    str.freeze

    x = str.instance_exec { proc { to_s } }
    assert_make_shareable(x)

    x = str.instance_exec { method(:to_s) }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:to_s).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:itself).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String(Kernel)#itself()>", exception: Ractor::Error)
=end
  end

  def test_shareable_proc_define_method_super_method_missing
    assert_ractor(<<~'RUBY', timeout: 30)
      iterations = 1_000_000

      class SuperFromShareableProcMethodMissingBase
        def method_missing(mid, *) = mid
      end

      class SuperFromShareableProcMethodMissingChild < SuperFromShareableProcMethodMissingBase
        BODY = Ractor.shareable_proc { super() }
        define_method(:foo, &BODY)
        define_method(:bar, &BODY)
      end

      [:foo, :bar].map do |mid|
        Ractor.new(mid, iterations) do |mid, iterations|
          obj = SuperFromShareableProcMethodMissingChild.new
          iterations.times do
            got = obj.__send__(mid)
            raise "#{mid} returned #{got.inspect}" unless got == mid
          end
        end
      end.each(&:value)
    RUBY
  end

  def test_shareable_proc_define_method_super_method_entry
    assert_ractor(<<~'RUBY', timeout: 30)
      iterations = 1_000_000

      class SuperFromShareableProcBase
        def foo = :foo
        def bar = :bar
      end

      class SuperFromShareableProcChild < SuperFromShareableProcBase
        BODY = Ractor.shareable_proc { super() }
        define_method(:foo, &BODY)
        define_method(:bar, &BODY)
      end

      [:foo, :bar].map do |mid|
        Ractor.new(mid, iterations) do |mid, iterations|
          obj = SuperFromShareableProcChild.new
          iterations.times do
            got = obj.__send__(mid)
            raise "#{mid} returned #{got.inspect}" unless got == mid
          end
        end
      end.each(&:value)
    RUBY
  end

  def test_shareability_error_uses_inspect
    x = (+"").instance_exec { method(:to_s) }
    def x.to_s
      raise "this should not be called"
    end
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()> because it refers unshareable objects", exception: Ractor::Error)
  end

  def test_sending_exception_with_backtrace
    assert_ractor(<<~'RUBY')
      def build_error
        raise "Test"
      rescue => error
        error
      end

      error = build_error
      refute_empty error.backtrace
      refute_empty error.backtrace_locations

      backtrace, backtrace_locations = Ractor.new(error) do |error2|
        [error2.backtrace, error2.backtrace_locations]
      end.value

      assert_equal error.backtrace, backtrace
      refute_empty backtrace_locations
    RUBY
  end

  def test_sending_exception_with_array_backtrace
    assert_ractor(<<~'RUBY')
      error = StandardError.new
      error.set_backtrace(["foo", "bar"])
      refute_empty error.backtrace
      assert_nil error.backtrace_locations

      backtrace, backtrace_locations = Ractor.new(error) do |error2|
        [error2.backtrace, error2.backtrace_locations]
      end.value

      assert_equal error.backtrace, backtrace
      assert_nil backtrace_locations
    RUBY
  end

  def test_sending_object_with_broken_clone
    # Copying a message does not call the user-visible #clone, so a broken #clone cannot
    # break sending; the singleton class that defining #clone creates makes it uncopyable.
    assert_ractor(<<~'RUBY')
      o = Object.new
      def o.clone
        self
      end
      ractor = Ractor.new { Ractor.receive }
      error = assert_raise Ractor::Error do
        ractor.send(o)
      end
      assert_match "can not copy", error.message
    RUBY
  end

  def test_default_thread_group
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      Warning[:experimental] = false

      main_ractor_id = Thread.current.group.object_id
      ractor_id = Ractor.new { Thread.current.group.object_id }.value
      refute_equal main_ractor_id, ractor_id
    end;
  end
  def test_ractor_with_live_threads_terminates_without_waiting
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      # A Ractor that ends while a thread of its own is still running used to sit out
      # the one second poll in rb_thread_terminate_all(), once per Ractor.  Measure
      # against the same Ractors without a live thread, so that a busy machine, which
      # makes both of them slow, does not decide this.
      n = 5
      elapsed = ->(&blk) {
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        n.times { blk.call }
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      }

      base = elapsed.call { assert_equal :done, Ractor.new { :done }.value }
      live = elapsed.call { assert_equal :done, Ractor.new { Thread.new { sleep 10 }; :done }.value }

      # the bug costs a second per Ractor, so #{n} seconds here
      assert_operator live, :<, base + 2.0,
                      "#{n} Ractors with a live thread took #{live}s, without one #{base}s"
    RUBY
  end


  def test_class_instance_variables
    assert_ractor(<<~'RUBY')
      # Once we're in multi-ractor mode, the codepaths
      # for class instance variables are a bit different.
      Ractor.new {}.value

      class TestClass
        @a = 1
        @b = 2
        @c = 3
        @d = 4
      end

      assert_equal 4, TestClass.remove_instance_variable(:@d)
      assert_nil TestClass.instance_variable_get(:@d)
      assert_equal 4, TestClass.instance_variable_set(:@d, 4)
      assert_equal 4, TestClass.instance_variable_get(:@d)
    RUBY
  end


  def test_class_variables
    # [Bug #22072]
    assert_ractor(<<~'RUBY')
      module Foo
        def self.foo = @@foo
      end

      Foo.class_variable_set(:@@foo, 1)

      10.times { |i| Foo.class_variable_set(:"@@bar#{i}", i) }

      assert_equal(Foo.foo, 1)
    RUBY
  end

  def test_struct_instance_variables
    assert_ractor(<<~'RUBY')
      StructIvar = Struct.new(:member) do
        def initialize(*)
          super
          @ivar = "ivar"
        end
        attr_reader :ivar
      end
      obj = StructIvar.new("member")
      obj_copy = Ractor.new { Ractor.receive }.send(obj).value
      assert_equal obj.ivar, obj_copy.ivar
      refute_same obj.ivar, obj_copy.ivar
      assert_equal obj.member, obj_copy.member
      refute_same obj.member, obj_copy.member
    RUBY
  end

  def test_move_nested_hash_during_gc_with_yjit
    assert_ractor(<<~'RUBY', timeout: 20, args: [{ "RUBY_YJIT_ENABLE" => "1" }])
      GC.stress = true
      hash = { foo: { bar: "hello" }, baz: { qux: "there" } }
      result = Ractor.new { Ractor.receive }.send(hash, move: true).value
      assert_equal "hello", result[:foo][:bar]
      assert_equal "there", result[:baz][:qux]
    RUBY
  end

  def test_create_many_ports_with_gc_stress
    # Rebuilding the ports table on insertion can run GC under the ractor lock.
    # It is a prohibited lock ordering, asserted in vm_lock_enter() on RUBY_DEBUG builds.
    assert_ractor(<<~'RUBY')
      r = Ractor.new { Ractor.receive } # enter multi-ractor mode and keep it
      begin
        GC.stress = true
        ports = 40.times.map { Ractor::Port.new }
      ensure
        GC.stress = false
      end
      assert_equal 40, ports.count
      ports.each(&:close)
      r.send(nil)
      r.join
    RUBY
  end

  def test_fork_child_gc_pins_shareable_objects
    # A forked child re-enters single-Ractor mode while the Ractors it had before the
    # fork leave their objspaces behind, so its local GC still has to pin shareable
    # objects instead of collecting them.
    assert_ractor(<<~'RUBY')
      port = Ractor::Port.new
      Ractor.new(port) { |p| p << Ractor::Port.new; Ractor.receive }
      foreign_port = port.receive # a Port owned by, and allocated in, the other Ractor
      pid = fork { 100_000.times { +"x" }; exit!(0) }
      _, status = Process.waitpid2(pid)
      assert_predicate status, :success?
      assert_instance_of Ractor::Port, foreign_port
    RUBY
  end if Process.respond_to?(:fork)

  def test_fork_raise_isolation_error
    assert_ractor(<<~'RUBY')
      ractor = Ractor.new do
        Process.fork
      rescue Ractor::IsolationError => e
        e
      end
      assert_equal Ractor::IsolationError, ractor.value.class
    RUBY
  end if Process.respond_to?(:fork)

  def test_at_exit_raise_isolation_error
    assert_ractor(<<~'RUBY')
      ractor = Ractor.new do
        at_exit { }
      rescue Ractor::IsolationError => e
        e
      end
      assert_equal Ractor::IsolationError, ractor.value.class
    RUBY
  end

  def test_END_raise_isolation_error
    assert_ractor(<<~'RUBY', ignore_stderr: true)
      ractor = Ractor.new do
        END { nil }
      rescue Ractor::IsolationError => e
        e
      end
      assert_equal Ractor::IsolationError, ractor.value.class
    RUBY
  end

  def test_require_raises_and_no_ractor_belonging_issue
    assert_ractor(<<~'RUBY')
      require "tempfile"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("raise 'uh oh'")
      f.flush
      err_msg = Ractor.new(f.path) do |path|
        begin
          require path
        rescue RuntimeError => e
          e.message # had confirm belonging issue here
        else
          nil
        end
      end.value
      assert_equal "uh oh", err_msg
    RUBY
  end

  def test_require_non_string
    assert_ractor(<<~'RUBY')
      require "tempfile"
      require "pathname"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("")
      f.flush
      result = Ractor.new(f.path) do |path|
        require Pathname.new(path)
        "success"
      end.value
      assert_equal "success", result
    RUBY
  end

  # Ex: Rubygems redefines require before single-ractor mode is cancelled. The redefined require
  # from a gem like rubygems should run in the main Ractor regardless of whether the gem is loaded
  # before or after single ractor mode is cancelled.
  #
  # Uses assert_separately rather than assert_ractor: these tests must start out in single-ractor
  # mode, and assert_ractor cancels it by creating a Ractor before the test body runs.
  def test_redefined_require_before_single_ractor_mode_cancelled
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      refute defined?(Gem), "rubygems must not be loaded"
      refute Object.private_method_defined?(:__ractor_original_require), "must still be in single-ractor mode"

      require "tempfile"
      require "pathname"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("")
      f.flush
      old = $-w; $-w = nil
      class << Ractor
        alias __orig_ractor_require _require
        def _require(feature)
          (Ractor.current[:required] ||= []) << [self.inspect, __method__, feature.to_s]
          __orig_ractor_require(feature)
        end
      end
      module Kernel
        alias some_original_require require
        def require(feature)
          (Ractor.current[:required] ||= []) << [self.inspect, __method__, feature.to_s]
          some_original_require(feature)
        end
      end
      $-w = old
      result = Ractor.new(f.path) do |path|
        require Pathname.new(path)
        Ractor.current[:required]
      end.value
      assert_equal [["Ractor", :_require, f.path]], result
      assert_equal ["nil", :require, f.path], Ractor.current[:required]&.first
    RUBY
  end

  # Ex: Rubygems redefines require after single-ractor mode is cancelled. The redefined require
  # from a gem like rubygems should run in the main Ractor regardless of whether the gem is loaded
  # before or after single ractor mode is cancelled.
  #
  # Uses assert_separately rather than assert_ractor: these tests must start out in single-ractor
  # mode, and assert_ractor cancels it by creating a Ractor before the test body runs.
  def test_redefined_require_after_single_ractor_mode_cancelled
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      refute defined?(Gem), "rubygems must not be loaded"
      refute Object.private_method_defined?(:__ractor_original_require), "must still be in single-ractor mode"

      require "tempfile"
      require "pathname"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("")
      f.flush
      old = $-w; $-w = nil
      class << Ractor
        alias __orig_ractor_require _require
        def _require(feature)
          (Ractor.current[:required] ||= []) << [self.inspect, __method__, feature.to_s]
          __orig_ractor_require(feature)
        end
      end
      $-w = old
      result = Ractor.new(f.path) do |path|
        require Pathname.new(path)
        Ractor.current[:required]
      end.value
      assert_equal [["Ractor", :_require, f.path]], result
      assert_nil Ractor.current[:required]
      old = $-w; $-w = nil
      module Kernel
        alias some_original_require require
        def require(feature)
          (Ractor.current[:required] ||= []) << [self.inspect, __method__, feature.to_s]
          some_original_require(feature)
        end
      end
      $-w = old
      result = Ractor.new(f.path) do |path|
        require Pathname.new(path)
        Ractor.current[:required]
      end.value
      assert_equal [["Ractor", :_require, f.path]], result
      assert_equal ["nil", :require, f.path], Ractor.current[:required]&.first
    RUBY
  end

  # [Bug #21398]
  def test_port_receive_dnt_with_port_send
    omit 'unstable on windows and macos-14' if RUBY_PLATFORM =~ /mswin|mingw|darwin/
    assert_ractor(<<~'RUBY', timeout: 90)
      THREADS = 10
      JOBS_PER_THREAD = 50
      ARRAY_SIZE = 20_000
      def ractor_job(job_count, array_size)
        port = Ractor::Port.new
        workers = (1..4).map do |i|
          Ractor.new(port) do |job_port|
            while job = Ractor.receive
              result = job.map { |x| x * 2 }.sum
              job_port.send result
            end
          end
        end
        jobs = Array.new(job_count) { Array.new(array_size) { rand(1000) } }
        jobs.each_with_index do |job, i|
          w_idx = i % 4
          workers[w_idx].send(job)
        end
        results = []
        jobs.size.times do
          result = port.receive # dnt receive
          results << result
        end
        results
      end
      threads = []
      # creates 40 ractors (THREADSx4)
      THREADS.times do
        threads << Thread.new do
          ractor_job(JOBS_PER_THREAD, ARRAY_SIZE)
        end
      end
      threads.each(&:join)
    RUBY
  end

  # [Bug #20146]
  def test_max_cpu_1
    assert_ractor(<<~'RUBY', args: [{ "RUBY_MAX_CPU" => "1" }])
      assert_equal :ok, Ractor.new { :ok }.value
    RUBY
  end

  def test_mn_threads
    # Ideally, we would assert that vm->ractor.sched.max_cpu equals sysconf(_SC_NPROCESSORS_ONLN)
    # when RUBY_MAX_CPU is not set.
    assert_ractor(<<~'RUBY', args: [{ "RUBY_MN_THREADS" => "1" }])
      require "etc"
      n = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 8
      rs = n.times.map { Ractor.new { :ok } }
      assert_equal [:ok] * n, rs.map(&:value)
    RUBY
  end

  def test_symbol_proc_is_shareable
    pr = :symbol.to_proc
    assert_make_shareable(pr)
  end

  # [Bug #21775]
  def test_ifunc_proc_not_shareable
    h = Hash.new { self }
    pr = h.to_proc
    assert_unshareable(pr, /not supported yet/, exception: RuntimeError)
  end

  def test_copy_unshareable_object_error_message
    assert_ractor(<<~'RUBY')
      pr = proc {}
      err = assert_raise(Ractor::Error) do
        Ractor.new(pr) {}.join
      end
      assert_match(/can not copy Proc object/, err.message)
    RUBY
  end

  def test_ractor_new_raises_isolation_error_if_outer_variables_are_accessed
    assert_raise(Ractor::IsolationError) do
      channel = Ractor::Port.new
      Ractor.new(channel) do
        inbound_work = Ractor::Port.new
        channel << inbound_work
      end
    end
  end

  def test_ractor_new_raises_isolation_error_if_proc_uses_yield
    assert_raise(Ractor::IsolationError) do
      Ractor.new do
        yield
      end
    end
  end

  def test_ractor_does_not_inherit_fiber_storage
    assert_ractor(<<~'RUBY')
      Fiber[:key] = "creator"
      assert_nil Ractor.new { Fiber[:key] }.value
    RUBY
  end

  def test_detailed_message_in_ractor
    # The error decoration gems (error_highlight, did_you_mean, and
    # syntax_suggest) are loaded lazily on the first error display. In a
    # non-main Ractor the require is delegated to the main Ractor, so the
    # decorations must appear there too. [Feature #21951]
    assert_ractor(<<~'RUBY', args: ["--enable=gems"], ignore_stderr: true)
      message = Ractor.new do
        begin
          1.timess
        rescue NoMethodError => e
          e.detailed_message(highlight: false)
        end
      end.value
      assert_include(message, "timess")
      assert_include(message, "Did you mean?")
    RUBY
  end

  # With per-Ractor GC, registering, storing and running a finalizer all belong to the
  # object's Ractor, so defining one on another Ractor's object (shareable included) is
  # rejected.
  def test_define_finalizer_on_foreign_object
    omit 'per-Ractor objspace semantics of the default GC' unless GC.config[:implementation] == 'default'
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      r = Ractor.new do
        results = []
        own = Object.new
        ObjectSpace.define_finalizer(own, proc {})
        results << :own_ok
        begin
          ObjectSpace.define_finalizer(String, proc {})  # main's class
          results << :define_did_not_raise
        rescue Ractor::IsolationError
          results << :define_raised
        end
        begin
          ObjectSpace.undefine_finalizer(String)
          results << :undefine_did_not_raise
        rescue Ractor::IsolationError
          results << :undefine_raised
        end
        results
      end
      assert_equal [:own_ok, :define_raised, :undefine_raised], r.value
      GC.verify_internal_consistency
    RUBY
  end

  # ObjectSpace.each_object enumerates every object in the calling Ractor's own objspace plus
  # the shareable objects of other live Ractors (never their unshareable ones).
  def test_each_object_own_all_and_foreign_shareables
    omit 'per-Ractor objspace semantics of the default GC' unless GC.config[:implementation] == 'default'
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      class Marker; end
      main_un = 5.times.map { Marker.new }
      main_sh = 3.times.map { Ractor.make_shareable(Marker.new) }
      ready = Ractor::Port.new
      ch = Ractor.new(ready) do |ready_port|
        un = 7.times.map { Marker.new }               # unshareable: must not be visible
        sh = 4.times.map { Ractor.make_shareable(Marker.new) }
        ready_port << :built
        Ractor.receive                                # keep this objspace alive
        [un.size, sh.size]
      end
      ready.receive                                   # the child finished building markers

      seen = 0
      ObjectSpace.each_object(Marker) { seen += 1 }
      # own 8 (5 unshareable + 3 shareable) + the child's 4 shareable
      assert_equal 12, seen

      ch.send(:go)
      ch.value
      # keep the roots alive across the scan
      assert_equal 5, main_un.size
      assert_equal 3, main_sh.size
    RUBY
  end

  # A Ractor.new that fails with IsolationError (stillborn) must still clean up the
  # half-created objspace (regression guard for double enumeration / use-after-free).
  def test_stillborn_ractor_gc
    assert_ractor(<<~'RUBY', timeout: 60)
      x = 42 # capturing an outer local makes Ractor.new raise IsolationError
      worker = Ractor.new { loop { break if Ractor.receive == :quit } }
      assert_raise(Ractor::IsolationError) { Ractor.new { x } }
      10.times { GC.start; 500.times { Object.new } }
      GC.verify_internal_consistency
      worker.send(:quit)
      worker.value
      100.times do |i|
        assert_raise(Ractor::IsolationError) { Ractor.new { x } }
        if (i % 20).zero?
          Ractor.new { :ok }.value
          GC.start
        end
      end
      GC.start
      GC.verify_internal_consistency
    RUBY
  end

  # Moving a CoW shared-root String must not steal its buffer (regression guard for the
  # remaining sharers reading freed memory).
  def test_move_shared_root_string_keeps_buffer
    assert_ractor(<<~'RUBY', timeout: 60)
      10.times do
        r = Ractor.new { Ractor.receive.bytesize; :done }
        f = "x" * 4096
        f.instance_variable_set(:@x, []) # unshareable ivar => moved, not passed by reference
        f.freeze
        g = f.dup                # shares f's buffer -> f is a shared root
        h = f[10, 3000]          # a long substring shares the buffer too
        r.send(f, move: true)
        r.value
        GC.start
        10.times { "z" * 4096 }
        assert_equal "x" * 4096, g
        assert_equal "x" * 3000, h
      end
    RUBY
  end

  # Ractor::Port.new must not deadlock under GC.stress (regression guard for a stress GC
  # triggered by malloc while the ractor lock is held).
  def test_port_new_under_gc_stress
    assert_ractor(<<~'RUBY', timeout: 90)
      GC.stress = true
      ports = 4.times.map { Ractor::Port.new }
      GC.stress = false
      assert_equal 4, ports.size
    RUBY
  end
  def test_port_receive_timeout
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      port = Ractor::Port.new

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_nil port.receive(timeout: 0.1)
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0, :>=, 0.1

      # a message that is already there wins over the timeout
      port << :a
      assert_equal :a, port.receive(timeout: 10)

      # timeout: 0 polls
      assert_nil port.receive(timeout: 0)
      port << :b
      assert_equal :b, port.receive(timeout: 0)
    RUBY
  end

  def test_receive_timeout_on_mn_thread
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      # a Ractor's thread is an M:N thread: the timeout must not need a native thread
      r = Ractor.new do
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        [Ractor.receive(timeout: 0.1), Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0]
      end
      v, elapsed = r.value
      assert_nil v
      assert_operator elapsed, :>=, 0.1
    RUBY
  end

  def test_select_timeout
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      p1, p2 = Ractor::Port.new, Ractor::Port.new
      assert_nil Ractor.select(p1, p2, timeout: 0.1)

      p2 << :b
      assert_equal [p2, :b], Ractor.select(p1, p2, timeout: 10)
    RUBY
  end

  def test_receive_timeout_racing_with_send
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      # the timeout and a send aim at the same instant: both wake the waiter
      results = []
      300.times do
        port = Ractor::Port.new
        th = Thread.new(port) {|p| sleep 0.001; p << :msg }
        results << port.receive(timeout: 0.001)
        th.join
      end
      assert_empty results.uniq - [:msg, nil]
    RUBY
  end


  # Moving a Hash that has Hash keys must not lose entries (regression guard for inserting a
  # key before its contents are filled in, which corrupts its hash value).
  def test_move_hash_with_hash_keys
    assert_ractor(<<~'RUBY', timeout: 60)
      k1 = { a: 1 }; k2 = { b: 2 }
      h = { k1 => :v1, k2 => :v2, { c: { d: 3 } } => :v3 }
      r = Ractor.new { Ractor.receive }
      r.send(h, move: true)
      m = r.value
      assert_equal 3, m.size
      assert_equal :v1, m[{ a: 1 }]
      assert_equal :v2, m[{ b: 2 }]
      assert_equal :v3, m[{ c: { d: 3 } }]
    RUBY
  end

  # A copy send's in-flight snapshot must not be moved by GC.compact (the global
  # generic_fields entries and the dedup table are keyed by address; YJIT reproduced this
  # deterministically).
  def test_copy_genivar_snapshot_survives_compact
    omit 'GC.compact is unimplemented' unless GC.config[:implementation] == 'default'
    assert_ractor(<<~'RUBY', timeout: 60, args: [{ "RUBY_YJIT_ENABLE" => "1" }])
      port = Ractor::Port.new
      w = Ractor.new(port) do |po|
        mm = Ractor.receive
        res = mm.map { |ss| [ss, ss.frozen?, ss.instance_variable_get(:@sku)] }
        po.send(res)
      end
      items = 4.times.map do |i|
        s = +"item-#{i}"
        s.instance_variable_set(:@sku, "SKU#{1000 + i}")
        s.freeze
      end
      w.send(items)
      GC.compact
      res = port.receive
      res.each_with_index do |(txt, fz, sku), i|
        assert_equal "item-#{i}", txt
        assert fz
        assert_equal "SKU#{1000 + i}", sku
      end
    RUBY
  end

  # A monitor entry holds a port of the monitoring Ractor, and the exit token is sent
  # through it, so that Ractor's wrapper must stay alive while the entry exists.
  def test_monitor_keeps_the_monitoring_ractor_alive
    assert_ractor(<<~'RUBY', timeout: 60)
      long = Ractor.new { Ractor.receive }
      Ractor.new(long) { |l| l.monitor(Ractor::Port.new) }.value
      GC.start                 # used to collect the monitoring Ractor's wrapper
      3000.times { Object.new }
      GC.start(full_mark: true)
      long.send(:bye)
      assert_equal :bye, long.value
    RUBY
  end

  # Port IDs are per-Ractor, so two monitoring Ractors can have the same port ID.
  # Ractor#unmonitor must match both the owning Ractor and the port ID, otherwise
  # it can remove a different Ractor's monitor entry.
  def test_unmonitor_does_not_remove_other_ractors_monitor
    assert_ractor(<<~'RUBY', timeout: 15)
      target = Ractor.new { Ractor.receive }

      b = Ractor.new(target) do |t|
        t.monitor(p = Ractor::Port.new)
        Ractor.main << :ready
        p.receive
      end

      Ractor.receive  # b's monitor is registered

      a = Ractor.new(target) do |t|
        t.monitor(p = Ractor::Port.new)
        t.unmonitor(p)
        t << :terminate
        p.close
        begin; p.receive; rescue Ractor::ClosedError; :ok; end
      end

      assert_equal :ok, a.value
      assert_equal :exited, b.value
    RUBY
  end

  # move must preserve the class of a String/Array/Hash subclass.
  def test_move_preserves_subclass
    assert_ractor(<<~'RUBY', timeout: 60)
      class MyStr < String; end
      class MyArr < Array; end
      class MyHash < Hash; end
      s = MyStr.new("hello"); a = MyArr.new([1, 2]); h = MyHash.new; h[:k] = 1
      r = Ractor.new { 3.times.map { Ractor.receive } }
      r.send(s, move: true); r.send(a, move: true); r.send(h, move: true)
      rs, ra, rh = r.value
      assert_equal [MyStr, MyArr, MyHash], [rs.class, ra.class, rh.class]
      assert_equal "hello", rs
      assert_equal [1, 2], ra
      assert_equal 1, rh[:k]
    RUBY
  end

  def test_move_preflight_matchdata_leaves_graph_intact
    assert_ractor(<<~'RUBY', timeout: 60)
      sibling = +"hello"
      m = "foo".match(Class.new(Regexp).new("o"))
      r = Ractor.new { Ractor.receive }
      refute Ractor.shareable?(m.regexp), "the Regexp subclass must be unshareable for this test"
      r.send([sibling, m], move: true) rescue Ractor::Error # the Regexp subclass is unshareable
      assert_equal "hello", sibling
    RUBY
  end

  def test_bignum_to_s
    assert_ractor(<<~'RUBY')
      8.times.map do
        Ractor.new do
          1_000.times do |i|
            v = (2**96 - 1) + i
            s = v.to_s
            # round-trip through str2big (uses the same cache)
            raise "bad to_s: #{s.inspect}" unless Integer(s) == v
          end
        end
      end.each(&:join)
    RUBY
  end

  def test_io_is_not_shareable
    io = File.open(IO::NULL)
    begin
      assert_unshareable(io, "can not make shareable object for #{io.inspect}",
                         exception: Ractor::Error)
      # freezing an IO does not make it shareable either
      io.freeze
      refute Ractor.shareable?(io)
      assert_raise(Ractor::Error) { Ractor.make_shareable(io) }
    ensure
      io.close
    end
  end

  def assert_make_shareable(obj)
    refute Ractor.shareable?(obj), "object was already shareable"
    Ractor.make_shareable(obj)
    assert Ractor.shareable?(obj), "object didn't become shareable"
  end

  def assert_unshareable(obj, msg=nil, exception: Ractor::IsolationError)
    refute Ractor.shareable?(obj), "object is already shareable"
    assert_raise_with_message(exception, msg) do
      Ractor.make_shareable(obj)
    end
    refute Ractor.shareable?(obj), "despite raising, object became shareable"
  end
  # $~ can hold the MatchData that a move hollows out in place.  The husk keeps
  # the old RMatch body, so a later match must allocate instead of reusing it
  # (a reused husk stays frozen and keeps its Ractor::MovedObject shape).
  def test_move_matchdata_kept_in_backref
    assert_ractor(<<~'RUBY', timeout: 60)
      r = Ractor.new { Ractor.receive }
      "abc123xyz".match(/([a-z]+)(\d+)/)      # $~ holds the MatchData
      r.send($~, move: true)                   # husked in place; $~ still points at it
      m = "qqq777".match(/([a-z]+)(\d+)/)
      assert_instance_of MatchData, m
      refute_predicate m, :frozen?
      assert_equal ["qqq777", "qqq", "777"], [m[0], m[1], m[2]]
      r.value
    RUBY
  end

  # String#dup of a frozen string shares the original's bytes, and for an embedded
  # string those bytes live in its slot.  Moving the original must leave that slot
  # alone: the sharer reads it for as long as it lives.
  def test_move_string_sharing_its_embedded_bytes
    assert_ractor(<<~'RUBY', timeout: 60)
      [24, 100, 300].each do |len|
        r = Ractor.new { Ractor.receive }
        str = "x" * len
        str.instance_variable_set(:@iv, [])   # unshareable, so it is moved
        str.freeze
        dup = str.dup                         # reads str's bytes in place
        r.send(str, move: true)
        assert_equal "x" * len, dup, "corrupted for length #{len}"
        r.value
      end
    RUBY
  end

  # A frozen array is handed out as a shared root as it is, so a subseq of an embedded
  # one reads the elements out of its slot.  Moving the original must leave that slot
  # alone, and must not let it move afterwards: the sharer has no other copy.
  def test_move_array_sharing_its_embedded_elements
    assert_ractor(<<~'RUBY', timeout: 60)
      [8, 20, 40].each do |len|
        r = Ractor.new { Ractor.receive }
        ary = Array.new(len) { |i| i + 1 }    # embedded
        ary.instance_variable_set(:@iv, [])   # unshareable, so it is moved
        ary.freeze
        sharer = ary[1, len - 2]              # reads ary's elements in place
        r.send(ary, move: true)
        assert_equal (2..len - 1).to_a, sharer, "corrupted for length #{len}"

        begin
          GC.verify_compaction_references(expand_heap: true, toward: :empty)
        rescue NotImplementedError
          # no compaction on this platform
        end
        assert_equal (2..len - 1).to_a, sharer, "corrupted by compaction, length #{len}"
        r.value
      end
    RUBY
  end

  def test_io_priority_wait_on_mn_thread
    omit 'POLLPRI/MSG_OOB semantics differ on windows' if RUBY_PLATFORM =~ /mswin|mingw/
    # A timeout-less IO#wait(IO::PRIORITY) on an M:N thread must take the
    # blocking path: the M:N scheduler has no event for POLLPRI and used to
    # register nothing yet park the thread forever.
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      require 'socket'
      r = Ractor.new do
        serv = TCPServer.new("127.0.0.1", 0)
        c = TCPSocket.new("127.0.0.1", serv.addr[1])
        s = serv.accept
        t = Thread.new { c.wait(IO::PRIORITY, nil) }
        sleep 0.5
        s.send("!", Socket::MSG_OOB)
        woken = t.join(5)
        [serv, c, s].each(&:close)
        woken ? :ok : :timeout
      end
      assert_equal :ok, r.value
    RUBY
  end
  def test_port_queue_dropped_when_port_unreachable
    omit 'not fixed for mmtk: it never calls rb_ractor_finish_marking, where the reap runs' unless GC.config[:implementation] == 'default'
    assert_ractor(<<~'RUBY')
      200.times do
        port = Ractor::Port.new
        Ractor.new(port) { |p| p << Ractor::Port.new; nil }.join
      end
      8.times { GC.start }
      # A dropped message holding a port used to root the sending Ractor, and with it
      # that Ractor's whole objspace, for the life of the process: every one of the 200
      # survived.  A few of the last still can -- the reap needs a second full mark, and
      # a conservative stack scan holds whatever it holds -- so this is not exact.
      assert_operator ObjectSpace.each_object(Ractor).count, :<, 20
    RUBY
  end

end
