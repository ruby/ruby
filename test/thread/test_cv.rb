# frozen_string_literal: false
require 'test/unit'
require 'thread'
require 'tmpdir'

class TestConditionVariable < Test::Unit::TestCase
  ConditionVariable = Thread::ConditionVariable
  Mutex = Thread::Mutex

  def test_initialized
    assert_raise(TypeError) {
      ConditionVariable.allocate.wait(nil)
    }
  end

  def test_condvar_signal_and_wait
    mutex = Mutex.new
    condvar = ConditionVariable.new
    result = []
    mutex.synchronize do
      t = Thread.new do
        mutex.synchronize do
          result << 1
          condvar.signal
        end
      end

      result << 0
      condvar.wait(mutex)
      result << 2
      t.join
    end
    assert_equal([0, 1, 2], result)
  end

  def test_condvar_wait_exception_handling
    # Calling wait in the only thread running should raise a ThreadError of
    # 'stopping only thread'
    mutex = Mutex.new
    condvar = ConditionVariable.new

    locked = false
    thread = Thread.new do
      Thread.current.abort_on_exception = false
      mutex.synchronize do
        begin
          condvar.wait(mutex)
        rescue Exception
          locked = mutex.locked?
          raise
        end
      end
    end

    until thread.stop?
      sleep(0.1)
    end

    thread.raise Interrupt, "interrupt a dead condition variable"
    assert_raise(Interrupt) { thread.value }
    assert(locked)
  end

  def test_condvar_wait_and_broadcast
    nr_threads = 3
    threads = Array.new
    mutex = Mutex.new
    condvar = ConditionVariable.new
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
  end

  def test_condvar_wait_deadlock
    assert_in_out_err([], <<-INPUT, /\Afatal\nNo live threads left\. Deadlock/, [])
      require "thread"

      mutex = Mutex.new
      cv = ConditionVariable.new

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
    mutex = Mutex.new
    condvar = ConditionVariable.new

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
    mutex = Mutex.new
    condvar = ConditionVariable.new
    timeout = 0.3
    locked = false

    t0 = Time.now
    mutex.synchronize do
      begin
        condvar.wait(mutex, timeout)
      ensure
        locked = mutex.locked?
      end
    end
    t1 = Time.now
    t = t1-t0

    assert_operator(timeout*0.9, :<, t)
    assert(locked)
  end

  def test_condvar_nolock
    mutex = Mutex.new
    condvar = ConditionVariable.new

    assert_raise(ThreadError) {condvar.wait(mutex)}
  end

  def test_condvar_nolock_2
    mutex = Mutex.new
    condvar = ConditionVariable.new

    Thread.new do
      assert_raise(ThreadError) {condvar.wait(mutex)}
    end.join
  end

  def test_condvar_nolock_3
    mutex = Mutex.new
    condvar = ConditionVariable.new

    Thread.new do
      assert_raise(ThreadError) {condvar.wait(mutex, 0.1)}
    end.join
  end

  def test_condvar_empty_signal
    mutex = Mutex.new
    condvar = ConditionVariable.new

    assert_nothing_raised(Exception) { mutex.synchronize {condvar.signal} }
  end

  def test_condvar_empty_broadcast
    mutex = Mutex.new
    condvar = ConditionVariable.new

    assert_nothing_raised(Exception) { mutex.synchronize {condvar.broadcast} }
  end

  def test_dup
    bug9440 = '[ruby-core:59961] [Bug #9440]'
    condvar = ConditionVariable.new
    assert_raise(NoMethodError, bug9440) do
      condvar.dup
    end
  end

  (DumpableCV = ConditionVariable.dup).class_eval {remove_method :marshal_dump}

  def test_dump
    bug9674 = '[ruby-core:61677] [Bug #9674]'
    condvar = ConditionVariable.new
    assert_raise_with_message(TypeError, /#{ConditionVariable}/, bug9674) do
      Marshal.dump(condvar)
    end

    condvar = DumpableCV.new
    assert_raise_with_message(TypeError, /internal Array/, bug9674) do
      Marshal.dump(condvar)
    end
  end
end
