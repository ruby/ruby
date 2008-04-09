require 'test/unit'
require 'thread'

class TestThread < Test::Unit::TestCase
  class Thread < ::Thread
    def self.new(*)
      th = super
      th.abort_on_exception = true
      th
    end
  end

  def test_mutex_synchronize
    m = Mutex.new
    r = 0
    max = 100
    (1..max).map{
      Thread.new{
        i=0
        while i<max*max
          i+=1
          m.synchronize{
            r += 1
          }
        end
      }
    }.each{|e|
      e.join
    }
    assert_equal(max * max * max, r)
  end

  def test_condvar
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

  def test_condvar_wait_not_owner
    mutex = Mutex.new
    condvar = ConditionVariable.new

    assert_raises(ThreadError) { condvar.wait(mutex) }
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
    assert_raises(Interrupt) { thread.value }
    assert(locked)
  end

  def test_local_barrier
    dir = File.dirname(__FILE__)
    lbtest = File.join(dir, "lbtest.rb")
    $:.unshift File.join(File.dirname(dir), 'ruby')
    require 'envutil'
    $:.shift
    10.times {
      result = `#{EnvUtil.rubybin} #{lbtest}`
      assert(!$?.coredump?, '[ruby-dev:30653]')
      assert_equal("exit.", result[/.*\Z/], '[ruby-dev:30653]')
    }
  end
end

class TestThreadGroup < Test::Unit::TestCase
  def test_thread_init
    thgrp = ThreadGroup.new
    Thread.new{
      thgrp.add(Thread.current)
      assert_equal(thgrp, Thread.new{sleep 1}.group)
    }.join
  end

  def test_frozen_thgroup
    thgrp = ThreadGroup.new
    Thread.new{
      thgrp.add(Thread.current)
      thgrp.freeze
      assert_raise(ThreadError) do
        Thread.new{1}.join
      end
    }.join
  end

  def test_enclosed_thgroup
    thgrp = ThreadGroup.new
    thgrp.enclose
    Thread.new{
      assert_raise(ThreadError) do
        thgrp.add(Thread.current)
      end
      assert_nothing_raised do
        Thread.new{1}.join
      end
    }.join
  end
end
