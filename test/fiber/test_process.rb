# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberProcess < Test::Unit::TestCase
  TRUE_CMD = RUBY_PLATFORM =~ /mswin|mingw/ ? "exit 0" : "true"

  def test_process_wait
    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        pid = Process.spawn(TRUE_CMD)
        Process.wait(pid)

        # TODO test that scheduler was invoked.

        assert_predicate $?, :success?
      end
    end.join
  end

  def test_system
    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        system(TRUE_CMD)

        # TODO test that scheduler was invoked (currently it's not).

        assert_predicate $?, :success?
      end
    end.join
  end

  def test_system_faulty_process_wait
    Thread.new do
      scheduler = Scheduler.new

      def scheduler.process_wait(pid, flags)
        Fiber.blocking{Process.wait(pid, flags)}

        # Don't return `Process::Status` instance.
        return false
      end

      Fiber.set_scheduler scheduler

      Fiber.schedule do
        assert_raise TypeError do
          system(TRUE_CMD)
        end
      end
    end.join
  end

  def test_fork
    omit 'fork not supported' unless Process.respond_to?(:fork)

    pid = Process.fork{}

    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        Process.wait(pid)

        assert_predicate $?, :success?
      end
    end.join
  end
end
