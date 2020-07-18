# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberIO < Test::Unit::TestCase
  MESSAGE = "Hello World"

  def test_read
    skip "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair

    unless i.nonblock? && o.nonblock?
      i.close
      o.close
      skip "I/O is not non-blocking!"
    end

    message = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber do
        message = i.read(20)
        i.close
      end

      Fiber do
        o.write("Hello World")
        o.close
      end
    end

    thread.join

    assert_equal MESSAGE, message
    assert_predicate(i, :closed?)
    assert_predicate(o, :closed?)
  end
  
  def test_heavy_read
    skip unless defined?(UNIXSocket)

    16.times.map do
      thread = Thread.new do
        i, o = UNIXSocket.pair
        
        scheduler = Scheduler.new
        Thread.current.scheduler = scheduler

        Fiber do
          message = i.read(20)
          i.close
        end

        Fiber do
          o.write("Hello World")
          o.close
        end
      end
    end.each(&:join)
  end
end
