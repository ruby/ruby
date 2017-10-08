# frozen_string_literal: false
require "monitor"

require "test/unit"

class TestMonitor < Test::Unit::TestCase
  Queue = Thread::Queue

  def setup
    @monitor = Monitor.new
  end

  def test_enter
    ary = []
    queue = Queue.new
    th = Thread.start {
      queue.pop
      @monitor.enter
      for i in 6 .. 10
        ary.push(i)
        Thread.pass
      end
      @monitor.exit
    }
    th2 = Thread.start {
      @monitor.enter
      queue.enq(nil)
      for i in 1 .. 5
        ary.push(i)
        Thread.pass
      end
      @monitor.exit
    }
    assert_join_threads([th, th2])
    assert_equal((1..10).to_a, ary)
  end

  def test_enter_second_after_killed_thread
    th = Thread.start {
      @monitor.enter
      Thread.current.kill
      @monitor.exit
    }
    th.join
    @monitor.enter
    @monitor.exit
    th2 = Thread.start {
      @monitor.enter
      @monitor.exit
    }
    assert_join_threads([th, th2])
  end

  def test_synchronize
    ary = []
    queue = Queue.new
    th = Thread.start {
      queue.pop
      @monitor.synchronize do
        for i in 6 .. 10
          ary.push(i)
          Thread.pass
        end
      end
    }
    th2 = Thread.start {
      @monitor.synchronize do
        queue.enq(nil)
        for i in 1 .. 5
          ary.push(i)
          Thread.pass
        end
      end
    }
    assert_join_threads([th, th2])
    assert_equal((1..10).to_a, ary)
  end

  def test_killed_thread_in_synchronize
    ary = []
    queue = Queue.new
    t1 = Thread.start {
      queue.pop
      @monitor.synchronize {
        ary << :t1
      }
    }
    t2 = Thread.start {
      queue.pop
      @monitor.synchronize {
        ary << :t2
      }
    }
    t3 = Thread.start {
      @monitor.synchronize do
        queue.enq(nil)
        queue.enq(nil)
        assert_equal([], ary)
        t1.kill
        t2.kill
        ary << :main
      end
      assert_equal([:main], ary)
    }
    assert_join_threads([t1, t2, t3])
  end

  def test_try_enter
    queue1 = Queue.new
    queue2 = Queue.new
    th = Thread.start {
      queue1.deq
      @monitor.enter
      queue2.enq(nil)
      queue1.deq
      @monitor.exit
      queue2.enq(nil)
    }
    th2 = Thread.start {
      assert_equal(true, @monitor.try_enter)
      @monitor.exit
      queue1.enq(nil)
      queue2.deq
      assert_equal(false, @monitor.try_enter)
      queue1.enq(nil)
      queue2.deq
      assert_equal(true, @monitor.try_enter)
    }
    assert_join_threads([th, th2])
  end

  def test_try_enter_second_after_killed_thread
    th = Thread.start {
      assert_equal(true, @monitor.try_enter)
      Thread.current.kill
      @monitor.exit
    }
    th.join
    assert_equal(true, @monitor.try_enter)
    @monitor.exit
    th2 = Thread.start {
      assert_equal(true, @monitor.try_enter)
      @monitor.exit
    }
    assert_join_threads([th, th2])
  end

  def test_mon_locked_and_owned
    queue1 = Queue.new
    queue2 = Queue.new
    th = Thread.start {
      @monitor.enter
      queue1.enq(nil)
      queue2.deq
      @monitor.exit
      queue1.enq(nil)
    }
    queue1.deq
    assert(@monitor.mon_locked?)
    assert(!@monitor.mon_owned?)

    queue2.enq(nil)
    queue1.deq
    assert(!@monitor.mon_locked?)

    @monitor.enter
    assert @monitor.mon_locked?
    assert @monitor.mon_owned?
    @monitor.exit

    @monitor.synchronize do
      assert @monitor.mon_locked?
      assert @monitor.mon_owned?
    end
  end

  def test_cond
    cond = @monitor.new_cond

    a = "foo"
    queue1 = Queue.new
    th = Thread.start do
      queue1.deq
      @monitor.synchronize do
        a = "bar"
        cond.signal
      end
    end
    th2 = Thread.start do
      @monitor.synchronize do
        queue1.enq(nil)
        assert_equal("foo", a)
        result1 = cond.wait
        assert_equal(true, result1)
        assert_equal("bar", a)
      end
    end
    assert_join_threads([th, th2])
  end

  def test_timedwait
    cond = @monitor.new_cond
    b = "foo"
    queue2 = Queue.new
    th = Thread.start do
      queue2.deq
      @monitor.synchronize do
        b = "bar"
        cond.signal
      end
    end
    th2 = Thread.start do
      @monitor.synchronize do
        queue2.enq(nil)
        assert_equal("foo", b)
        result2 = cond.wait(0.1)
        assert_equal(true, result2)
        assert_equal("bar", b)
      end
    end
    assert_join_threads([th, th2])

    c = "foo"
    queue3 = Queue.new
    th = Thread.start do
      queue3.deq
      @monitor.synchronize do
        c = "bar"
        cond.signal
      end
    end
    th2 = Thread.start do
      @monitor.synchronize do
        assert_equal("foo", c)
        result3 = cond.wait(0.1)
        assert_equal(true, result3) # wait always returns true in Ruby 1.9
        assert_equal("foo", c)
        queue3.enq(nil)
        result4 = cond.wait
        assert_equal(true, result4)
        assert_equal("bar", c)
      end
    end
    assert_join_threads([th, th2])

#     d = "foo"
#     cumber_thread = Thread.start {
#       loop do
#         @monitor.synchronize do
#           d = "foo"
#         end
#       end
#     }
#     queue3 = Queue.new
#     Thread.start do
#       queue3.pop
#       @monitor.synchronize do
#         d = "bar"
#         cond.signal
#       end
#     end
#     @monitor.synchronize do
#       queue3.enq(nil)
#       assert_equal("foo", d)
#       result5 = cond.wait
#       assert_equal(true, result5)
#       # this thread has priority over cumber_thread
#       assert_equal("bar", d)
#     end
#     cumber_thread.kill
  end
end
