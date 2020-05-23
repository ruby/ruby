# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberIO < Test::Unit::TestCase
  MESSAGE = "Hello World"

  def test_read
    skip unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    skip unless i.nonblock? && o.nonblock?

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
  end
end
