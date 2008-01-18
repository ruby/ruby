require 'test/unit'

class TestThread < Test::Unit::TestCase
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
