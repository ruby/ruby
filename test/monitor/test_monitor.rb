require "monitor"
require "thread"

require "test/unit"

class TestMonitor < Test::Unit::TestCase
  def setup
    @monitor = Monitor.new
  end

  def test_enter
    ary = []
    th = Thread.start {
      Thread.pass
      @monitor.enter
      for i in 6 .. 10
        ary.push(i)
        Thread.pass
      end
      @monitor.exit
    }
    @monitor.enter
    for i in 1 .. 5
      ary.push(i)
      Thread.pass
    end
    @monitor.exit
    th.join
    assert_equal((1..10).to_a, ary)
  end

  def test_synchronize
    ary = []
    th = Thread.start {
      Thread.pass
      @monitor.synchronize do
        for i in 6 .. 10
          ary.push(i)
          Thread.pass
        end
      end
    }
    @monitor.synchronize do
      for i in 1 .. 5
        ary.push(i)
        Thread.pass
      end
    end
    th.join
    assert_equal((1..10).to_a, ary)
  end

  def test_try_enter
    queue = Queue.new
    th = Thread.start {
      queue.deq
      @monitor.enter
      queue.deq
      @monitor.exit
    }
    assert_equal(true, @monitor.try_enter)
    @monitor.exit
    queue.enq(Object.new)
    assert_equal(false, @monitor.try_enter)
    queue.enq(Object.new)
    assert_equal(true, @monitor.try_enter)
  end

  def test_cond
    cond = @monitor.new_cond

    a = "foo"
    Thread.start do
      Thread.pass
      @monitor.synchronize do
        a = "bar"
        cond.signal
      end
    end
    @monitor.synchronize do
      assert_equal("foo", a)
      result1 = cond.wait
      assert_equal(true, result1)
      assert_equal("bar", a)
    end

    b = "foo"
    Thread.start do
      Thread.pass
      @monitor.synchronize do
        b = "bar"
        cond.signal
      end
    end
    @monitor.synchronize do
      assert_equal("foo", b)
      result2 = cond.wait(0.1)
      assert_equal(true, result2)
      assert_equal("bar", b)
    end

    c = "foo"
    Thread.start do
      sleep(0.2)
      @monitor.synchronize do
        c = "bar"
        cond.signal
      end
    end
    @monitor.synchronize do
      assert_equal("foo", c)
      result3 = cond.wait(0.1)
      assert_equal(false, result3)
      assert_equal("foo", c)
      result4 = cond.wait
      assert_equal(true, result4)
      assert_equal("bar", c)
    end

    d = "foo"
    cumber_thread = Thread.start {
      loop do
        @monitor.synchronize do
          d = "foo"
        end
      end
    }
    Thread.start do
      Thread.pass
      @monitor.synchronize do
        d = "bar"
        cond.signal
      end
    end
    @monitor.synchronize do
      assert_equal("foo", d)
      result5 = cond.wait
      assert_equal(true, result5)
      # this thread has priority over cumber_thread
      assert_equal("bar", d)
    end
    cumber_thread.kill
  end
end
