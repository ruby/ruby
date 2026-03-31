# frozen_string_literal: true
require 'test/unit'
require 'timeout'
require_relative '../../fiber/scheduler'

class TestSchedulerInterruptHandling < Test::Unit::TestCase
  def setup
    pend("No fork support") unless Process.respond_to?(:fork)
    require '-test-/scheduler'
  end

  # Test without Thread.handle_interrupt - should work regardless of fix
  def test_without_handle_interrupt_signal_works
    IO.pipe do |input, output|
      pid = fork do
        STDERR.reopen(output)

        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler

        Signal.trap(:INT) do
          ::Thread.current.raise(Interrupt)
        end

        Fiber.schedule do
          # Yield to the scheduler:
          sleep(0)

          Bug::Scheduler.blocking_loop(output)
        end
      end

      output.close
      assert_equal "x", input.read(1)

      Process.kill(:INT, pid)

      reaper = Thread.new do
        Process.waitpid2(pid)
      end

      unless reaper.join(10)
        Process.kill(:KILL, pid)
      end

      _, status = reaper.value

      # It should be interrupted (not killed):
      assert_not_equal 0, status.exitstatus
      assert_equal true, status.signaled?
      assert_equal Signal.list["INT"], status.termsig
    end
  end
end
