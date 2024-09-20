# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'

class TestThreadConditionVariable < Test::Unit::TestCase
  ConditionVariable = Thread::ConditionVariable
  Mutex = Thread::Mutex

  def test_condvar_signal_and_wait
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new
    result = []
    woken = nil
    mutex.synchronize do
      t = Thread.new do
        mutex.synchronize do
          result << 1
          condvar.signal
        end
      end

      result << 0
      woken = condvar.wait(mutex)
      result << 2
      t.join
    end
    assert_equal([0, 1, 2], result)
    assert(woken)
  end

  def test_condvar_wait_exception_handling
    # Calling wait in the only thread running should raise a ThreadError of
    # 'stopping only thread'
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new

    locked = false
    thread = Thread.new do
      Thread.current.abort_on_exception = false
      mutex.synchronize do
        assert_raise(Interrupt) {
          condvar.wait(mutex)
        }
        locked = mutex.locked?
      end
    end

    until thread.stop?
      sleep(0.1)
    end

    thread.raise Interrupt, "interrupt a dead condition variable"
    thread.join
    assert(locked)
  end

  def test_condvar_wait_and_broadcast
    nr_threads = 3
    threads = Array.new
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new
    result = []

    nr_threads.times do |i|
      threads[i] = Thread.new do
        mutex.synchronize do
          result << "C1"
          condvar.wait mutex
          result << "C2"
        end
      end
    end
    sleep 0.1
    mutex.synchronize do
      result << "P1"
      condvar.broadcast
      result << "P2"
    end
    Timeout.timeout(5) do
      nr_threads.times do |i|
        threads[i].join
      end
    end

    assert_equal ["C1", "C1", "C1", "P1", "P2", "C2", "C2", "C2"], result
  ensure
    threads.each(&:kill)
    threads.each(&:join)
  end

  def test_condvar_wait_deadlock
    assert_in_out_err([], <<-INPUT, /\Afatal\nNo live threads left\. Deadlock/, [])
      mutex = Thread::Mutex.new
      cv = Thread::ConditionVariable.new

      klass = nil
      mesg = nil
      begin
        mutex.lock
        cv.wait mutex
        mutex.unlock
      rescue Exception => e
        klass = e.class
        mesg = e.message
      end
      puts klass
      print mesg
INPUT
  end

  def test_condvar_wait_deadlock_2
    nr_threads = 3
    threads = Array.new
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new

    nr_threads.times do |i|
      if (i != 0)
        mutex.unlock
      end
      threads[i] = Thread.new do
        mutex.synchronize do
          condvar.wait mutex
        end
      end
      mutex.lock
    end

    assert_raise(Timeout::Error) do
      Timeout.timeout(0.1) { condvar.wait mutex }
    end
    mutex.unlock
    threads.each(&:kill)
    threads.each(&:join)
  end

  def test_condvar_timed_wait
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new
    timeout = 0.3
    locked = false
    woken = true

    t0 = Time.now
    mutex.synchronize do
      begin
        woken = condvar.wait(mutex, timeout)
      ensure
        locked = mutex.locked?
      end
    end
    t1 = Time.now
    t = t1-t0

    assert_operator(timeout*0.9, :<, t)
    assert(locked)
    assert_nil(woken)
  end

  def test_condvar_nolock
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new

    assert_raise(ThreadError) {condvar.wait(mutex)}
  end

  def test_condvar_nolock_2
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new

    Thread.new do
      assert_raise(ThreadError) {condvar.wait(mutex)}
    end.join
  end

  def test_condvar_nolock_3
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new

    Thread.new do
      assert_raise(ThreadError) {condvar.wait(mutex, 0.1)}
    end.join
  end

  def test_condvar_empty_signal
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new

    assert_nothing_raised(Exception) { mutex.synchronize {condvar.signal} }
  end

  def test_condvar_empty_broadcast
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new

    assert_nothing_raised(Exception) { mutex.synchronize {condvar.broadcast} }
  end

  def test_dup
    bug9440 = '[ruby-core:59961] [Bug #9440]'
    condvar = Thread::ConditionVariable.new
    assert_raise(NoMethodError, bug9440) do
      condvar.dup
    end
  end

  (DumpableCV = ConditionVariable.dup).class_eval {remove_method :marshal_dump}

  def test_dump
    bug9674 = '[ruby-core:61677] [Bug #9674]'
    condvar = Thread::ConditionVariable.new
    assert_raise_with_message(TypeError, /#{ConditionVariable}/, bug9674) do
      Marshal.dump(condvar)
    end

    condvar = DumpableCV.new
    assert_raise(TypeError, bug9674) do
      Marshal.dump(condvar)
    end
  end

  def test_condvar_fork
    mutex = Thread::Mutex.new
    condvar = Thread::ConditionVariable.new
    thrs = (1..10).map do
      Thread.new { mutex.synchronize { condvar.wait(mutex) } }
    end
    thrs.each { 3.times { Thread.pass } }
    pid = fork do
      th = Thread.new do
        mutex.synchronize { condvar.wait(mutex) }
        :ok
      end
      until th.join(0.01)
        mutex.synchronize { condvar.broadcast }
      end
      exit!(th.value == :ok ? 0 : 1)
    end
    _, s = Process.waitpid2(pid)
    assert_predicate s, :success?, 'no segfault [ruby-core:86316] [Bug #14634]'
    until thrs.empty?
      mutex.synchronize { condvar.broadcast }
      thrs.delete_if { |t| t.join(0.01) }
    end
  end if Process.respond_to?(:fork)
end
