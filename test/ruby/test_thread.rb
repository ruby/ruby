# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'
require "rbconfig/sizeof"
require "timeout"

class TestThread < Test::Unit::TestCase
  class Thread < ::Thread
    Threads = []
    def self.new(*)
      th = super
      Threads << th
      th
    end
  end

  def setup
    Thread::Threads.clear
  end

  def teardown
    Thread::Threads.each do |t|
      t.kill if t.alive?
      begin
        t.join
      rescue Exception
      end
    end
  end

  def test_inspect
    line = __LINE__+1
    th = Module.new {break module_eval("class C\u{30b9 30ec 30c3 30c9} < Thread; self; end")}.start{}
    s = th.inspect
    assert_include(s, "::C\u{30b9 30ec 30c3 30c9}:")
    assert_include(s, " #{__FILE__}:#{line} ")
    assert_equal(s, th.to_s)
  ensure
    th.join
  end

  def test_inspect_with_fiber
    inspect1 = inspect2 = nil

    Thread.new{
      inspect1 = Thread.current.inspect
      Fiber.new{
        inspect2 = Thread.current.inspect
      }.resume
    }.join

    assert_equal inspect1, inspect2, '[Bug #13689]'
  end

  def test_main_thread_variable_in_enumerator
    assert_equal Thread.main, Thread.current

    Thread.current.thread_variable_set :foo, "bar"

    thread, value = Fiber.new {
      Fiber.yield [Thread.current, Thread.current.thread_variable_get(:foo)]
    }.resume

    assert_equal Thread.current, thread
    assert_equal Thread.current.thread_variable_get(:foo), value
  end

  def test_thread_variable_in_enumerator
    Thread.new {
      Thread.current.thread_variable_set :foo, "bar"

      thread, value = Fiber.new {
        Fiber.yield [Thread.current, Thread.current.thread_variable_get(:foo)]
      }.resume

      assert_equal Thread.current, thread
      assert_equal Thread.current.thread_variable_get(:foo), value
    }.join
  end

  def test_thread_variables
    assert_equal [], Thread.new { Thread.current.thread_variables }.join.value

    t = Thread.new {
      Thread.current.thread_variable_set(:foo, "bar")
      Thread.current.thread_variables
    }
    assert_equal [:foo], t.join.value
  end

  def test_thread_variable?
    Thread.new { assert_not_send([Thread.current, :thread_variable?, "foo"]) }.value
    t = Thread.new {
      Thread.current.thread_variable_set("foo", "bar")
    }.join

    assert_send([t, :thread_variable?, "foo"])
    assert_send([t, :thread_variable?, :foo])
    assert_not_send([t, :thread_variable?, :bar])
  end

  def test_thread_variable_strings_and_symbols_are_the_same_key
    t = Thread.new {}.join
    t.thread_variable_set("foo", "bar")
    assert_equal "bar", t.thread_variable_get(:foo)
  end

  def test_thread_variable_frozen
    t = Thread.new { }.join
    t.freeze
    assert_raise(FrozenError) do
      t.thread_variable_set(:foo, "bar")
    end
  end

  def test_mutex_synchronize
    m = Thread::Mutex.new
    r = 0
    num_threads = 10
    loop=100
    (1..num_threads).map{
      Thread.new{
        loop.times{
          m.synchronize{
            tmp = r
            # empty and waste loop for making thread preemption
            100.times {
            }
            r = tmp + 1
          }
        }
      }
    }.each{|e|
      e.join
    }
    assert_equal(num_threads*loop, r)
  end

  def test_mutex_synchronize_yields_no_block_params
    bug8097 = '[ruby-core:53424] [Bug #8097]'
    assert_empty(Thread::Mutex.new.synchronize {|*params| break params}, bug8097)
  end

  def test_local_barrier
    dir = File.dirname(__FILE__)
    lbtest = File.join(dir, "lbtest.rb")
    $:.unshift File.join(File.dirname(dir), 'ruby')
    $:.shift
    3.times {
      `#{EnvUtil.rubybin} #{lbtest}`
      assert_not_predicate($?, :coredump?, '[ruby-dev:30653]')
    }
  end

  def test_priority
    c1 = c2 = 0
    run = true
    t1 = Thread.new { c1 += 1 while run }
    t1.priority = 3
    t2 = Thread.new { c2 += 1 while run }
    t2.priority = -3
    assert_equal(3, t1.priority)
    assert_equal(-3, t2.priority)
    sleep 0.5
    5.times do
      assert_not_predicate(t1, :stop?)
      assert_not_predicate(t2, :stop?)
      break if c1 > c2
      sleep 0.1
    end
    run = false
    t1.kill
    t2.kill
    assert_operator(c1, :>, c2, "[ruby-dev:33124]") # not guaranteed
    t1.join
    t2.join
  end

  def test_new
    assert_raise(ThreadError) do
      Thread.new
    end

    t1 = Thread.new { sleep }
    assert_raise(ThreadError) do
      t1.instance_eval { initialize { } }
    end

    t2 = Thread.new(&method(:sleep).to_proc)
    assert_raise(ThreadError) do
      t2.instance_eval { initialize { } }
    end

  ensure
    t1&.kill&.join
    t2&.kill&.join
  end

  def test_new_symbol_proc
    bug = '[ruby-core:80147] [Bug #13313]'
    assert_ruby_status([], "#{<<-"begin;"}\n#{<<-'end;'}", bug)
    begin;
      exit("1" == Thread.start(1, &:to_s).value)
    end;
  end

  def test_join
    t = Thread.new { sleep }
    assert_nil(t.join(0.05))

  ensure
    t&.kill&.join
  end

  def test_join2
    ok = false
    t1 = Thread.new { ok = true; sleep }
    Thread.pass until ok
    Thread.pass until t1.stop?
    t2 = Thread.new do
      Thread.pass while ok
      t1.join(0.01)
    end
    t3 = Thread.new do
      ok = false
      t1.join
    end
    assert_nil(t2.value)
    t1.wakeup
    assert_equal(t1, t3.value)

  ensure
    t1&.kill&.join
    t2&.kill&.join
    t3&.kill&.join
  end

  def test_join_argument_conversion
    t = Thread.new {}
    assert_raise(TypeError) {t.join(:foo)}

    limit = Struct.new(:to_f, :count).new(0.05)
    assert_same(t, t.join(limit))
  end

  { 'FIXNUM_MAX' => RbConfig::LIMITS['FIXNUM_MAX'],
    'UINT64_MAX' => RbConfig::LIMITS['UINT64_MAX'],
    'INFINITY'   => Float::INFINITY
  }.each do |name, limit|
    define_method("test_join_limit_#{name}") do
      t = Thread.new {}
      assert_same t, t.join(limit), "limit=#{limit.inspect}"
    end
  end

  { 'minus_1'        => -1,
    'minus_0_1'      => -0.1,
    'FIXNUM_MIN'     => RbConfig::LIMITS['FIXNUM_MIN'],
    'INT64_MIN'      => RbConfig::LIMITS['INT64_MIN'],
    'minus_INFINITY' => -Float::INFINITY
  }.each do |name, limit|
    define_method("test_join_limit_negative_#{name}") do
      t = Thread.new { sleep }
      begin
        assert_nothing_raised(Timeout::Error) do
          Timeout.timeout(30) do
            assert_nil t.join(limit), "limit=#{limit.inspect}"
          end
        end
      ensure
        t.kill
      end
    end
  end

  def test_kill_main_thread
    assert_in_out_err([], <<-INPUT, %w(1), [])
      p 1
      Thread.kill Thread.current
      p 2
    INPUT
  end

  def test_kill_wrong_argument
    bug4367 = '[ruby-core:35086]'
    assert_raise(TypeError, bug4367) {
      Thread.kill(nil)
    }
    o = Object.new
    assert_raise(TypeError, bug4367) {
      Thread.kill(o)
    }
  end

  def test_kill_thread_subclass
    c = Class.new(Thread)
    t = c.new { sleep 10 }
    assert_nothing_raised { Thread.kill(t) }
    assert_equal(nil, t.value)
  end

  def test_exit
    s = 0
    Thread.new do
      s += 1
      Thread.exit
      s += 2
    end.join
    assert_equal(1, s)
  end

  def test_wakeup
    s = 0
    t = Thread.new do
      s += 1
      Thread.stop
      s += 1
    end
    Thread.pass until t.stop?
    sleep 1 if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled? # t.stop? behaves unexpectedly with --jit-wait
    assert_equal(1, s)
    t.wakeup
    Thread.pass while t.alive?
    assert_equal(2, s)
    assert_raise(ThreadError) { t.wakeup }
  ensure
    t&.kill&.join
  end

  def test_stop
    assert_in_out_err([], <<-INPUT, %w(2), [])
      begin
        Thread.stop
        p 1
      rescue ThreadError
        p 2
      end
    INPUT
  end

  def test_list
    assert_in_out_err([], <<-INPUT) do |r, e|
      t1 = Thread.new { sleep }
      Thread.pass
      t2 = Thread.new { loop { Thread.pass } }
      Thread.new { }.join
      p [Thread.current, t1, t2].map{|t| t.object_id }.sort
      p Thread.list.map{|t| t.object_id }.sort
    INPUT
      assert_equal(r.first, r.last)
      assert_equal([], e)
    end
  end

  def test_main
    assert_in_out_err([], <<-INPUT, %w(true false), [])
      p Thread.main == Thread.current
      Thread.new { p Thread.main == Thread.current }.join
    INPUT
  end

  def test_abort_on_exception
    assert_in_out_err([], <<-INPUT, %w(false 1), [])
      p Thread.abort_on_exception
      begin
        t = Thread.new {
          Thread.current.report_on_exception = false
          raise
        }
        Thread.pass until t.stop?
        p 1
      rescue
        p 2
      end
    INPUT

    assert_in_out_err([], <<-INPUT, %w(true 2), [])
      Thread.abort_on_exception = true
      p Thread.abort_on_exception
      begin
        Thread.new {
          Thread.current.report_on_exception = false
          raise
        }
        sleep 0.5
        p 1
      rescue
        p 2
      end
    INPUT

    assert_in_out_err(%w(--disable-gems -d), <<-INPUT, %w(false 2), %r".+")
      p Thread.abort_on_exception
      begin
        t = Thread.new { raise }
        Thread.pass until t.stop?
        p 1
      rescue
        p 2
      end
    INPUT

    assert_in_out_err([], <<-INPUT, %w(false true 2), [])
      p Thread.abort_on_exception
      begin
        ok = false
        t = Thread.new {
          Thread.current.report_on_exception = false
          Thread.pass until ok
          raise
        }
        t.abort_on_exception = true
        p t.abort_on_exception
        ok = 1
        sleep 1
        p 1
      rescue
        p 2
      end
    INPUT
  end

  def test_report_on_exception
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      q1 = Thread::Queue.new
      q2 = Thread::Queue.new

      assert_equal(true, Thread.report_on_exception,
                   "global flag is true by default")
      assert_equal(true, Thread.current.report_on_exception,
                   "the main thread has report_on_exception=true")

      Thread.report_on_exception = true
      Thread.current.report_on_exception = false
      assert_equal(true,
                   Thread.start {Thread.current.report_on_exception}.value,
                  "should not inherit from the parent thread but from the global flag")

      assert_warn("", "exception should be ignored silently when false") {
        th = Thread.start {
          Thread.current.report_on_exception = false
          q1.push(Thread.current.report_on_exception)
          raise "report 1"
        }
        assert_equal(false, q1.pop)
        Thread.pass while th.alive?
        assert_raise(RuntimeError) { th.join }
      }

      assert_warn(/report 2/, "exception should be reported when true") {
        th = Thread.start {
          q1.push(Thread.current.report_on_exception = true)
          raise "report 2"
        }
        assert_equal(true, q1.pop)
        Thread.pass while th.alive?
        assert_raise(RuntimeError) { th.join }
      }

      assert_warn("", "the global flag should not affect already started threads") {
        Thread.report_on_exception = false
        th = Thread.start {
          q2.pop
          q1.push(Thread.current.report_on_exception)
          raise "report 3"
        }
        q2.push(Thread.report_on_exception = true)
        assert_equal(false, q1.pop)
        Thread.pass while th.alive?
        assert_raise(RuntimeError) { th.join }
      }

      assert_warn(/report 4/, "should defaults to the global flag at the start") {
        Thread.report_on_exception = true
        th = Thread.start {
          q1.push(Thread.current.report_on_exception)
          raise "report 4"
        }
        assert_equal(true, q1.pop)
        Thread.pass while th.alive?
        assert_raise(RuntimeError) { th.join }
      }

      assert_warn(/report 5/, "should first report and then raise with report_on_exception + abort_on_exception") {
        th = Thread.start {
          Thread.current.report_on_exception = true
          Thread.current.abort_on_exception = true
          q2.pop
          raise "report 5"
        }
        assert_raise_with_message(RuntimeError, "report 5") {
          q2.push(true)
          Thread.pass while th.alive?
        }
        assert_raise(RuntimeError) { th.join }
      }
    end;
  end

  def test_ignore_deadlock
    if /mswin|mingw/ =~ RUBY_PLATFORM
      skip "can't trap a signal from another process on Windows"
    end
    assert_in_out_err([], <<-INPUT, %w(false :sig), [], :signal=>:INT, timeout: 1, timeout_error: nil)
      p Thread.ignore_deadlock
      q = Thread::Queue.new
      trap(:INT){q.push :sig}
      Thread.ignore_deadlock = true
      p q.pop
    INPUT
  end

  def test_status_and_stop_p
    a = ::Thread.new {
      Thread.current.report_on_exception = false
      raise("die now")
    }
    b = Thread.new { Thread.stop }
    c = Thread.new { Thread.exit }
    e = Thread.current
    Thread.pass while a.alive? or !b.stop? or c.alive?

    assert_equal(nil, a.status)
    assert_predicate(a, :stop?)

    assert_equal("sleep", b.status)
    assert_predicate(b, :stop?)

    assert_equal(false, c.status)
    assert_match(/^#<TestThread::Thread:.* dead>$/, c.inspect)
    assert_predicate(c, :stop?)

    es1 = e.status
    es2 = e.stop?
    assert_equal(["run", false], [es1, es2])
    assert_raise(RuntimeError) { a.join }
  ensure
    b&.kill&.join
    c&.join
  end

  def test_switch_while_busy_loop
    bug1402 = "[ruby-dev:38319] [Bug #1402]"
    flag = true
    th = Thread.current
    waiter = Thread.start {
      sleep 0.1
      flag = false
      sleep 1
      th.raise(bug1402)
    }
    assert_nothing_raised(RuntimeError, bug1402) do
      nil while flag
    end
    assert(!flag, bug1402)
  ensure
    waiter&.kill&.join
  end

  def test_thread_local
    t = Thread.new { sleep }

    assert_equal(false, t.key?(:foo))

    t["foo"] = "foo"
    t["bar"] = "bar"
    t["baz"] = "baz"

    assert_equal(true, t.key?(:foo))
    assert_equal(true, t.key?("foo"))
    assert_equal(false, t.key?(:qux))
    assert_equal(false, t.key?("qux"))

    assert_equal([:foo, :bar, :baz].sort, t.keys.sort)

  ensure
    t&.kill&.join
  end

  def test_thread_local_fetch
    t = Thread.new { sleep }

    assert_equal(false, t.key?(:foo))

    t["foo"] = "foo"
    t["bar"] = "bar"
    t["baz"] = "baz"

    x = nil
    assert_equal("foo", t.fetch(:foo, 0))
    assert_equal("foo", t.fetch(:foo) {x = true})
    assert_nil(x)
    assert_equal("foo", t.fetch("foo", 0))
    assert_equal("foo", t.fetch("foo") {x = true})
    assert_nil(x)

    x = nil
    assert_equal(0, t.fetch(:qux, 0))
    assert_equal(1, t.fetch(:qux) {x = 1})
    assert_equal(1, x)
    assert_equal(2, t.fetch("qux", 2))
    assert_equal(3, t.fetch("qux") {x = 3})
    assert_equal(3, x)

    e = assert_raise(KeyError) {t.fetch(:qux)}
    assert_equal(:qux, e.key)
    assert_equal(t, e.receiver)
  ensure
    t&.kill&.join
  end

  def test_thread_local_security
    Thread.new do
      Thread.current[:foo] = :bar
      Thread.current.freeze
      assert_raise(FrozenError) do
        Thread.current[:foo] = :baz
      end
    end.join
  end

  def test_thread_local_dynamic_symbol
    bug10667 = '[ruby-core:67185] [Bug #10667]'
    t = Thread.new {}.join
    key_str = "foo#{rand}"
    key_sym = key_str.to_sym
    t.thread_variable_set(key_str, "bar")
    assert_equal("bar", t.thread_variable_get(key_str), "#{bug10667}: string key")
    assert_equal("bar", t.thread_variable_get(key_sym), "#{bug10667}: symbol key")
  end

  def test_select_wait
    assert_nil(IO.select(nil, nil, nil, 0.001))
    t = Thread.new do
      IO.select(nil, nil, nil, nil)
    end
    Thread.pass until t.stop?
    assert_predicate(t, :alive?)
  ensure
    t&.kill&.join
  end

  def test_mutex_deadlock
    m = Thread::Mutex.new
    m.synchronize do
      assert_raise(ThreadError) do
        m.synchronize do
          assert(false)
        end
      end
    end
  end

  def test_mutex_interrupt
    m = Thread::Mutex.new
    m.lock
    t = Thread.new do
      m.lock
      :foo
    end
    Thread.pass until t.stop?
    t.kill
    assert_nil(t.value)
  end

  def test_mutex_illegal_unlock
    m = Thread::Mutex.new
    m.lock
    Thread.new do
      assert_raise(ThreadError) do
        m.unlock
      end
    end.join
  end

  def test_mutex_fifo_like_lock
    m1 = Thread::Mutex.new
    m2 = Thread::Mutex.new
    m1.lock
    m2.lock
    m1.unlock
    m2.unlock
    assert_equal(false, m1.locked?)
    assert_equal(false, m2.locked?)

    m3 = Thread::Mutex.new
    m1.lock
    m2.lock
    m3.lock
    m1.unlock
    m2.unlock
    m3.unlock
    assert_equal(false, m1.locked?)
    assert_equal(false, m2.locked?)
    assert_equal(false, m3.locked?)
  end

  def test_mutex_trylock
    m = Thread::Mutex.new
    assert_equal(true, m.try_lock)
    assert_equal(false, m.try_lock, '[ruby-core:20943]')

    Thread.new{
      assert_equal(false, m.try_lock)
    }.join

    m.unlock
  end

  def test_recursive_outer
    arr = []
    obj = Struct.new(:foo, :visited).new(arr, false)
    arr << obj
    def obj.hash
      self[:visited] = true
      super
      raise "recursive_outer should short circuit intermediate calls"
    end
    assert_nothing_raised {arr.hash}
    assert(obj[:visited], "obj.hash was not called")
  end

  def test_thread_instance_variable
    bug4389 = '[ruby-core:35192]'
    assert_in_out_err([], <<-INPUT, %w(), [], bug4389)
      class << Thread.current
        @data = :data
      end
    INPUT
  end

  def test_no_valid_cfp
    skip 'with win32ole, cannot run this testcase because win32ole redefines Thread#initialize' if defined?(WIN32OLE)
    bug5083 = '[ruby-dev:44208]'
    assert_equal([], Thread.new(&Module.method(:nesting)).value, bug5083)
    assert_instance_of(Thread, Thread.new(:to_s, &Class.new.method(:undef_method)).join, bug5083)
  end

  def make_handle_interrupt_test_thread1 flag
    r = []
    ready_q = Thread::Queue.new
    done_q = Thread::Queue.new
    th = Thread.new{
      begin
        Thread.handle_interrupt(RuntimeError => flag){
          begin
            ready_q << true
            done_q.pop
          rescue
            r << :c1
          end
        }
      rescue
        r << :c2
      end
    }
    ready_q.pop
    th.raise
    begin
      done_q << true
      th.join
    rescue
      r << :c3
    end
    r
  end

  def test_handle_interrupt
    [[:never, :c2],
     [:immediate, :c1],
     [:on_blocking, :c1]].each{|(flag, c)|
      assert_equal([flag, c], [flag] + make_handle_interrupt_test_thread1(flag))
    }
    # TODO: complex cases are needed.
  end

  def test_handle_interrupt_invalid_argument
    assert_raise(ArgumentError) {
      Thread.handle_interrupt(RuntimeError => :immediate) # no block
    }
    assert_raise(ArgumentError) {
      Thread.handle_interrupt(RuntimeError => :xyzzy) {}
    }
    assert_raise(TypeError) {
      Thread.handle_interrupt([]) {} # array
    }
  end

  def for_test_handle_interrupt_with_return
    Thread.handle_interrupt(Object => :never){
      Thread.current.raise RuntimeError.new("have to be rescured")
      return
    }
  rescue
  end

  def test_handle_interrupt_with_return
    assert_nothing_raised do
      for_test_handle_interrupt_with_return
      _dummy_for_check_ints=nil
    end
  end

  def test_handle_interrupt_with_break
    assert_nothing_raised do
      begin
        Thread.handle_interrupt(Object => :never){
          Thread.current.raise RuntimeError.new("have to be rescured")
          break
        }
      rescue
      end
      _dummy_for_check_ints=nil
    end
  end

  def test_handle_interrupt_blocking
    r = nil
    q = Thread::Queue.new
    e = Class.new(Exception)
    th_s = Thread.current
    th = Thread.start {
      assert_raise(RuntimeError) {
        Thread.handle_interrupt(Object => :on_blocking){
          begin
            q.pop
            Thread.current.raise RuntimeError, "will raise in sleep"
            r = :ok
            sleep
          ensure
            th_s.raise e, "raise from ensure", $@
          end
        }
      }
    }
    assert_raise(e) {q << true; th.join}
    assert_equal(:ok, r)
  end

  def test_handle_interrupt_and_io
    assert_in_out_err([], <<-INPUT, %w(ok), [])
      th_waiting = true
      q = Thread::Queue.new

      t = Thread.new {
        Thread.current.report_on_exception = false
        Thread.handle_interrupt(RuntimeError => :on_blocking) {
          q << true
          nil while th_waiting
          # async interrupt should be raised _before_ writing puts arguments
          puts "ng"
        }
      }

      q.pop
      t.raise RuntimeError
      th_waiting = false
      t.join rescue nil
      puts "ok"
    INPUT
  end

  def test_handle_interrupt_and_p
    assert_in_out_err([], <<-INPUT, %w(:ok :ok), [])
      th_waiting = false

      t = Thread.new {
        Thread.current.report_on_exception = false
        Thread.handle_interrupt(RuntimeError => :on_blocking) {
          th_waiting = true
          nil while th_waiting
          # p shouldn't provide interruptible point
          p :ok
          p :ok
        }
      }

      Thread.pass until th_waiting
      t.raise RuntimeError
      th_waiting = false
      t.join rescue nil
    INPUT
  end

  def test_handle_interrupted?
    q = Thread::Queue.new
    Thread.handle_interrupt(RuntimeError => :never){
      done = false
      th = Thread.new{
        q.push :e
        begin
          begin
            Thread.pass until done
          rescue
            q.push :ng1
          end
          begin
            Thread.handle_interrupt(Object => :immediate){} if Thread.pending_interrupt?
          rescue RuntimeError
            q.push :ok
          end
        rescue
          q.push :ng2
        ensure
          q.push :ng3
        end
      }
      q.pop
      th.raise
      done = true
      th.join
      assert_equal(:ok, q.pop)
    }
  end

  def test_thread_timer_and_ensure
    assert_normal_exit(<<_eom, 'r36492', timeout: 10)
    flag = false
    t = Thread.new do
      begin
        sleep
      ensure
        1 until flag
      end
    end

    Thread.pass until t.status == "sleep"

    t.kill
    t.alive? == true
    flag = true
    t.join
_eom
  end

  def test_uninitialized
    c = Class.new(Thread) {def initialize; end}
    assert_raise(ThreadError) { c.new.start }

    bug11959 = '[ruby-core:72732] [Bug #11959]'

    c = Class.new(Thread) {def initialize; exit; end}
    assert_raise(ThreadError, bug11959) { c.new }

    c = Class.new(Thread) {def initialize; raise; end}
    assert_raise(ThreadError, bug11959) { c.new }

    c = Class.new(Thread) {
      def initialize
        pending = pending_interrupt?
        super {pending}
      end
    }
    assert_equal(false, c.new.value, bug11959)
  end

  def test_backtrace
    Thread.new{
      assert_equal(Array, Thread.main.backtrace.class)
    }.join

    t = Thread.new{}
    t.join
    assert_equal(nil, t.backtrace)
  end

  def test_thread_timer_and_interrupt
    bug5757 = '[ruby-dev:44985]'
    pid = nil
    cmd = 'Signal.trap(:INT, "DEFAULT"); pipe=IO.pipe; Thread.start {Thread.pass until Thread.main.stop?; puts; STDOUT.flush}; pipe[0].read'
    opt = {}
    opt[:new_pgroup] = true if /mswin|mingw/ =~ RUBY_PLATFORM
    s, t, _err = EnvUtil.invoke_ruby(['-e', cmd], "", true, true, **opt) do |in_p, out_p, err_p, cpid|
      assert IO.select([out_p], nil, nil, 10), 'subprocess not ready'
      out_p.gets
      pid = cpid
      t0 = Time.now.to_f
      Process.kill(:SIGINT, pid)
      begin
        Timeout.timeout(10) { Process.wait(pid) }
      rescue Timeout::Error
        EnvUtil.terminate(pid)
        raise
      end
      t1 = Time.now.to_f
      [$?, t1 - t0, err_p.read]
    end
    assert_equal(pid, s.pid, bug5757)
    assert_equal([false, true, false, Signal.list["INT"]],
                 [s.exited?, s.signaled?, s.stopped?, s.termsig],
                 "[s.exited?, s.signaled?, s.stopped?, s.termsig]")
    assert_include(0..2, t, bug5757)
  end

  def test_thread_join_in_trap
    assert_separately [], <<-'EOS'
    Signal.trap(:INT, "DEFAULT")
    t0 = Thread.current
    assert_nothing_raised{
      t = Thread.new {Thread.pass until t0.stop?; Process.kill(:INT, $$)}

      Signal.trap :INT do
        t.join
      end

      t.join
    }
    EOS
  end

  def test_thread_value_in_trap
    assert_separately [], <<-'EOS'
    Signal.trap(:INT, "DEFAULT")
    t0 = Thread.current
    t = Thread.new {Thread.pass until t0.stop?; Process.kill(:INT, $$); :normal_end}

    Signal.trap :INT do
      t.value
    end
    assert_equal(:normal_end, t.value)
    EOS
  end

  def test_thread_join_current
    assert_raise(ThreadError) do
      Thread.current.join
    end
  end

  def test_thread_join_main_thread
    Thread.new(Thread.current) {|t|
      assert_raise(ThreadError) do
        t.join
      end
    }.join
  end

  def test_main_thread_status_at_exit
    assert_in_out_err([], <<-'INPUT', ["false false aborting"], [])
q = Thread::Queue.new
Thread.new(Thread.current) {|mth|
  begin
    q.push nil
    mth.run
    Thread.pass until mth.stop?
    p :mth_stopped # don't run if killed by rb_thread_terminate_all
  ensure
    puts "#{mth.alive?} #{mth.status} #{Thread.current.status}"
  end
}
q.pop
    INPUT
  end

  def test_thread_status_in_trap
    # when running trap handler, Thread#status must show "run"
    # Even though interrupted from sleeping function
    assert_in_out_err([], <<-INPUT, %w(sleep run), [])
      Signal.trap(:INT) {
        puts Thread.current.status
        exit
      }
      t = Thread.current

      Thread.new(Thread.current) {|mth|
        Thread.pass until t.stop?
        puts mth.status
        Process.kill(:INT, $$)
      }
      sleep 0.1
    INPUT
  end

  # Bug #7450
  def test_thread_status_raise_after_kill
    ary = []

    t = Thread.new {
      assert_raise(RuntimeError) do
        begin
          ary << Thread.current.status
          sleep #1
        ensure
          begin
            ary << Thread.current.status
            sleep #2
          ensure
            ary << Thread.current.status
          end
        end
      end
    }

    Thread.pass until ary.size >= 1
    Thread.pass until t.stop?
    t.kill  # wake up sleep #1
    Thread.pass until ary.size >= 2
    Thread.pass until t.stop?
    t.raise "wakeup" # wake up sleep #2
    Thread.pass while t.alive?
    assert_equal(ary, ["run", "aborting", "aborting"])
    t.join
  end

  def test_mutex_owned
    mutex = Thread::Mutex.new

    assert_equal(mutex.owned?, false)
    mutex.synchronize {
      # Now, I have the mutex
      assert_equal(mutex.owned?, true)
    }
    assert_equal(mutex.owned?, false)
  end

  def test_mutex_owned2
    begin
      mutex = Thread::Mutex.new
      th = Thread.new {
        # lock forever
        mutex.lock
        sleep
      }

      # acquired by another thread.
      Thread.pass until mutex.locked?
      assert_equal(mutex.owned?, false)
    ensure
      th&.kill&.join
    end
  end

  def test_mutex_unlock_on_trap
    assert_in_out_err([], <<-INPUT, %w(locked unlocked false), [])
      m = Thread::Mutex.new

      trapped = false
      Signal.trap("INT") { |signo|
        m.unlock
        trapped = true
        puts "unlocked"
      }

      m.lock
      puts "locked"
      Process.kill("INT", $$)
      Thread.pass until trapped
      puts m.locked?
    INPUT
  end

  def invoke_rec script, vm_stack_size, machine_stack_size, use_length = true
    env = {}
    env['RUBY_THREAD_VM_STACK_SIZE'] = vm_stack_size.to_s if vm_stack_size
    env['RUBY_THREAD_MACHINE_STACK_SIZE'] = machine_stack_size.to_s if machine_stack_size
    out, err, status = EnvUtil.invoke_ruby([env, '-e', script], '', true, true)
    assert_not_predicate(status, :signaled?, err)

    use_length ? out.length : out
  end

  def test_stack_size
    h_default = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', nil, nil, false))
    h_0 = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', 0, 0, false))
    h_large = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', 1024 * 1024 * 10, 1024 * 1024 * 10, false))

    assert_operator(h_default[:thread_vm_stack_size], :>, h_0[:thread_vm_stack_size],
                    "0 thread_vm_stack_size")
    assert_operator(h_default[:thread_vm_stack_size], :<, h_large[:thread_vm_stack_size],
                    "large thread_vm_stack_size")
    assert_operator(h_default[:thread_machine_stack_size], :>=, h_0[:thread_machine_stack_size],
                    "0 thread_machine_stack_size")
    assert_operator(h_default[:thread_machine_stack_size], :<=, h_large[:thread_machine_stack_size],
                    "large thread_machine_stack_size")
    assert_equal("ok", invoke_rec('print :ok', 1024 * 1024 * 100, nil, false))
  end

  def test_vm_machine_stack_size
    script = 'def rec; print "."; STDOUT.flush; rec; end; rec'
    size_default = invoke_rec script, nil, nil
    assert_operator(size_default, :>, 0, "default size")
    size_0 = invoke_rec script, 0, nil
    assert_operator(size_default, :>, size_0, "0 size")
    size_large = invoke_rec script, 1024 * 1024 * 10, nil
    assert_operator(size_default, :<, size_large, "large size")
  end

  def test_machine_stack_size
    # check machine stack size
    # Note that machine stack size may not change size (depend on OSs)
    script = 'def rec; print "."; STDOUT.flush; 1.times{1.times{1.times{rec}}}; end; Thread.new{rec}.join'
    vm_stack_size = 1024 * 1024
    size_default = invoke_rec script, vm_stack_size, nil
    size_0 = invoke_rec script, vm_stack_size, 0
    assert_operator(size_default, :>=, size_0, "0 size")
    size_large = invoke_rec script, vm_stack_size, 1024 * 1024 * 10
    assert_operator(size_default, :<=, size_large, "large size")
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_blocking_mutex_unlocked_on_fork
    bug8433 = '[ruby-core:55102] [Bug #8433]'

    mutex = Thread::Mutex.new
    mutex.lock

    th = Thread.new do
      mutex.synchronize do
        sleep
      end
    end

    Thread.pass until th.stop?
    mutex.unlock

    pid = Process.fork do
      exit(mutex.locked?)
    end

    th.kill

    pid, status = Process.waitpid2(pid)
    assert_equal(false, status.success?, bug8433)
  end if Process.respond_to?(:fork)

  def test_fork_in_thread
    bug9751 = '[ruby-core:62070] [Bug #9751]'
    f = nil
    th = Thread.start do
      unless f = IO.popen("-")
        STDERR.reopen(STDOUT)
        exit
      end
      Process.wait2(f.pid)
    end
    unless th.join(EnvUtil.apply_timeout_scale(30))
      Process.kill(:QUIT, f.pid)
      Process.kill(:KILL, f.pid) unless th.join(EnvUtil.apply_timeout_scale(1))
    end
    _, status = th.value
    output = f.read
    f.close
    assert_not_predicate(status, :signaled?, FailDesc[status, bug9751, output])
    assert_predicate(status, :success?, bug9751)
  end if Process.respond_to?(:fork)

  def test_fork_value
    bug18902 = "[Bug #18902]"
    th = Thread.start { sleep 2 }
    begin
      pid = fork do
        th.value
      end
      _, status = Process.wait2(pid)
      assert_predicate(status, :success?, bug18902)
    ensure
      th.kill
    end
  end if Process.respond_to?(:fork)

  def test_fork_while_locked
    m = Thread::Mutex.new
    thrs = []
    3.times do |i|
      thrs << Thread.new { m.synchronize { Process.waitpid2(fork{})[1] } }
    end
    thrs.each do |t|
      assert_predicate t.value, :success?, '[ruby-core:85940] [Bug #14578]'
    end
  end if Process.respond_to?(:fork)

  def test_fork_while_parent_locked
    skip 'needs fork' unless Process.respond_to?(:fork)
    m = Thread::Mutex.new
    nr = 1
    thrs = []
    m.synchronize do
      thrs = nr.times.map { Thread.new { m.synchronize {} } }
      thrs.each { Thread.pass }
      pid = fork do
        m.locked? or exit!(2)
        thrs = nr.times.map { Thread.new { m.synchronize {} } }
        m.unlock
        thrs.each { |t| t.join(1) == t or exit!(1) }
        exit!(0)
      end
      _, st = Process.waitpid2(pid)
      assert_predicate st, :success?, '[ruby-core:90312] [Bug #15383]'
    end
    thrs.each { |t| assert_same t, t.join(1) }
  end

  def test_fork_while_mutex_locked_by_forker
    skip 'needs fork' unless Process.respond_to?(:fork)
    m = Thread::Mutex.new
    m.synchronize do
      pid = fork do
        exit!(2) unless m.locked?
        m.unlock rescue exit!(3)
        m.synchronize {} rescue exit!(4)
        exit!(0)
      end
      _, st = Timeout.timeout(30) { Process.waitpid2(pid) }
      assert_predicate st, :success?, '[ruby-core:90595] [Bug #15430]'
    end
  end

  def test_subclass_no_initialize
    t = Module.new do
      break eval("class C\u{30b9 30ec 30c3 30c9} < Thread; self; end")
    end
    t.class_eval do
      def initialize
      end
    end
    assert_raise_with_message(ThreadError, /C\u{30b9 30ec 30c3 30c9}/) do
      t.new {}
    end
  end

  def test_thread_name
    t = Thread.start {sleep}
    sleep 0.001 until t.stop?
    assert_nil t.name
    s = t.inspect
    t.name = 'foo'
    assert_equal 'foo', t.name
    t.name = nil
    assert_nil t.name
    assert_equal s, t.inspect
  ensure
    t.kill
    t.join
  end

  def test_thread_invalid_name
    bug11756 = '[ruby-core:71774] [Bug #11756]'
    t = Thread.start {}
    assert_raise(ArgumentError, bug11756) {t.name = "foo\0bar"}
    assert_raise(ArgumentError, bug11756) {t.name = "foo".encode(Encoding::UTF_32BE)}
  ensure
    t.kill
    t.join
  end

  def test_thread_invalid_object
    bug11756 = '[ruby-core:71774] [Bug #11756]'
    t = Thread.start {}
    assert_raise(TypeError, bug11756) {t.name = []}
  ensure
    t.kill
    t.join
  end

  def test_thread_setname_in_initialize
    bug12290 = '[ruby-core:74963] [Bug #12290]'
    c = Class.new(Thread) {def initialize() self.name = "foo"; super; end}
    assert_equal("foo", c.new {Thread.current.name}.value, bug12290)
  end

  def test_thread_native_thread_id
    skip "don't support native_thread_id" unless Thread.method_defined?(:native_thread_id)
    assert_instance_of Integer, Thread.main.native_thread_id

    th1 = Thread.start{sleep}

    # newly created thread which doesn't run yet returns nil or integer
    assert_include [NilClass, Integer], th1.native_thread_id.class

    Thread.pass until th1.stop?

    # After a thread starts (and execute `sleep`), it returns native_thread_id
    assert_instance_of Integer, th1.native_thread_id

    th1.wakeup
    Thread.pass while th1.alive?

    # dead thread returns nil
    assert_nil th1.native_thread_id
  end

  def test_thread_interrupt_for_killed_thread
    opts = { timeout: 5, timeout_error: nil }

    # prevent SIGABRT from slow shutdown with MJIT
    opts[:reprieve] = 3 if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled?

    assert_normal_exit(<<-_end, '[Bug #8996]', **opts)
      Thread.report_on_exception = false
      trap(:TERM){exit}
      while true
        t = Thread.new{sleep 0}
        t.raise Interrupt
        Thread.pass # allow t to finish
      end
    _end
  end

  def test_signal_at_join
    if /mswin|mingw/ =~ RUBY_PLATFORM
      skip "can't trap a signal from another process on Windows"
      # opt = {new_pgroup: true}
    end
    assert_separately([], "#{<<~"{#"}\n#{<<~'};'}", timeout: 120)
    {#
      n = 1000
      sig = :INT
      trap(sig) {}
      IO.popen([EnvUtil.rubybin, "-e", "#{<<~"{#1"}\n#{<<~'};#1'}"], "r+") do |f|
        tpid = #{$$}
        sig = :#{sig}
        {#1
          STDOUT.sync = true
          while gets
            puts
            Process.kill(sig, tpid)
          end
        };#1
        assert_nothing_raised do
          n.times do
            w = Thread.start do
              sleep 30
            end
            begin
              f.puts
              f.gets
            ensure
              w.kill
              w.join
            end
          end
        end
        n.times do
          w = Thread.start { sleep 30 }
          begin
            f.puts
            f.gets
          ensure
            w.kill
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            w.join(30)
            t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            diff = t1 - t0
            assert_operator diff, :<=, 2
          end
        end
      end
    };
  end
end
