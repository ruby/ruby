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
          Timeout.timeout(0.01) do
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
end
