require 'test/unit'
require 'thread'
require_relative 'envutil'

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

    t = Thread.new{1}
    Thread.new{
      thgrp.add(Thread.current)
      thgrp.freeze
      assert_raise(ThreadError) do
        Thread.new{1}.join
      end
      assert_raise(ThreadError) do
        thgrp.add(t)
      end
      assert_raise(ThreadError) do
        ThreadGroup.new.add Thread.current
      end
    }.join
    t.join
  end

  def test_enclosed_thgroup
    thgrp = ThreadGroup.new
    assert_equal(false, thgrp.enclosed?)

    t = Thread.new{1}
    Thread.new{
      thgrp.add(Thread.current)
      thgrp.enclose
      assert_equal(true, thgrp.enclosed?)
      assert_nothing_raised do
        Thread.new{1}.join
      end
      assert_raise(ThreadError) do
        thgrp.add t
      end
      assert_raise(ThreadError) do
        ThreadGroup.new.add Thread.current
      end
    }.join
    t.join
  end
end
