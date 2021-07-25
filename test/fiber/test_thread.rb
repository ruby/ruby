# frozen_string_literal: true
require "test/unit"
require_relative 'scheduler'

class TestFiberThread < Test::Unit::TestCase
  def test_thread_join
    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      result = nil
      Fiber.schedule do
        result = Thread.new{:done}.value
      end

      scheduler.run
      result
    end

    assert_equal :done, thread.value
  end

  def test_thread_join_blocking
    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      result = nil
      Fiber.schedule do
        Fiber.new(blocking: true) do
          # This can deadlock if the blocking state is not taken into account:
          Thread.new do
            sleep(0)
            result = :done
          end.join
        end.resume
      end

      scheduler.run
      result
    end

    assert_equal :done, thread.value
  end
end
