# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

require 'timeout'

class TestFiberTimeout < Test::Unit::TestCase
  def test_timeout_after
    error = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        begin
          Timeout.timeout(0.001) do
            sleep(1)
          end
        rescue
          error = $!
        end
      end
    end

    thread.join

    assert_kind_of(Timeout::Error, error)
  end

  MESSAGE = "Hello World"

  def test_timeout_on_main_fiber
    message = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      assert_nil Fiber.current_scheduler

      Timeout.timeout(1) do
        message = MESSAGE
      end
    end

    thread.join

    assert_equal MESSAGE, message
  end
end
