# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberEnumerator < Test::Unit::TestCase
  MESSAGE = "Hello World"

  def test_read_characters
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair

    message = String.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      e = i.to_enum(:each_char)

      Fiber.schedule do
        o.write("Hello World")
        o.close
      end

      Fiber.schedule do
        begin
          while c = e.next
            message << c
          end
        rescue StopIteration
          # Ignore.
        end

        i.close
      end
    end

    thread.join

    assert_equal(MESSAGE, message)
    assert_predicate(i, :closed?)
    assert_predicate(o, :closed?)
  end
end
