# frozen_string_literal: false
require 'test/unit'
require 'monitor'

class TestMonitorMixin < Test::Unit::TestCase
  def test_cond
    a = "foo"
    a.extend(MonitorMixin)
    cond = a.new_cond
    queue1 = Queue.new
    th = Thread.start do
      queue1.deq
      a.synchronize do
        a.replace("bar")
        cond.signal
      end
    end
    th2 = Thread.start do
      a.synchronize do
        queue1.enq(nil)
        assert_equal("foo", a)
        result1 = cond.wait
        assert_equal(true, result1)
        assert_equal("bar", a)
      end
    end
    assert_join_threads([th, th2])
  end

  def test_initialize_twice
    a = Object.new
    a.extend(MonitorMixin)
    assert_raise(ThreadError) do
      a.send(:mon_initialize)
    end
  end
end
