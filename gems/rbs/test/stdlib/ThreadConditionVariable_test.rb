require_relative "test_helper"

class ThreadConditionVariableTest < StdlibTest
  target Thread::ConditionVariable
  using hook.refinement

  def test_broadcast
    cv = Thread::ConditionVariable.new
    cv.broadcast
  end

  def test_signal
    cv = Thread::ConditionVariable.new
    cv.signal
  end

  def test_wait
    mutex = Thread::Mutex.new
    cv = Thread::ConditionVariable.new
    flag = false
    threads = []

    threads << Thread.start do
      mutex.synchronize do
        cv.wait(mutex) until flag
      end
    end

    threads << Thread.start do
      mutex.synchronize do
        flag = true
        cv.broadcast
      end
    end

    threads.each(&:join)
  end

  def test_wait_with_timeout
    mutex = Thread::Mutex.new
    cv = Thread::ConditionVariable.new
    flag = false
    threads = []

    threads << Thread.start do
      mutex.synchronize do
        cv.wait(mutex, 1) until flag
      end
    end

    threads << Thread.start do
      mutex.synchronize do
        flag = true
        cv.broadcast
      end
    end

    threads.each(&:join)
  end
end
