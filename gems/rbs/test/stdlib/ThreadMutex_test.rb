require_relative "test_helper"

class ThreadMutexTest < StdlibTest
  target Thread::Mutex
  using hook.refinement

  def test_lock
    m = Thread::Mutex.new
    m.lock
  end

  def test_locked?
    m = Mutex.new
    m.locked?
    m.lock
    m.locked?
  end

  def test_owned?
    m = Mutex.new
    m.owned?
    m.lock
    Thread.new do
      m.owned?
    end.join
    m.owned?
  end

  def test_synchronize
    m = Mutex.new

    m.synchronize do
      "result"
    end

    m.synchronize do
      :result
    end

    m.synchronize do
    end
  end

  def test_try_lock
    m = Mutex.new
    m.try_lock
    m.try_lock
  end

  def test_unlock
    m = Mutex.new
    m.lock
    m.unlock
  end
end
