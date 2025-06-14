# frozen_string_literal: true
require "test/unit"
require "fiber"

class TestFiberCurrentRactor < Test::Unit::TestCase
  def setup
    omit unless defined? Ractor
  end

  def test_ractor_shareable
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber")
    begin;
      r = Ractor.new do
        Fiber.new do
          Fiber.current.class
        end.resume
      end
      assert_equal(Fiber, r.value)
    end;
  end

  def test_ractor_join_before_ractor_finished_in_fiber_scheduler_context
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber", require_relative: "scheduler")
    begin;
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler
      class << scheduler
        attr_reader :test_blockers
        def block(blocker, timeout=nil)
          (@test_blockers ||= []) << [blocker, timeout]
          super
        end
      end
      # in f1 (main fiber)
      ordering = []
      blocked_thread = nil
      Fiber.schedule do
        # in f2
        r = Ractor.new do
          # in f3
          sleep 0.5
        end
        ordering << "f2 before join"
        # Calling `r.join` should schedule us away from f2 back to f1. In f1, we end the script
        # and then Scheduler#run is called, which blocks on IO.select. When the ractor is finished,
        # it resumes fiber f2.
        blocked_thread = Thread.current
        r.join
        ordering << "f2 after join"
      end
      ordering << "f1 thread finish"
      expected_ordering = ["f2 before join", "f1 thread finish", "f2 after join"]
      at_exit do
        assert_equal expected_ordering, ordering
        assert_equal 1, scheduler.test_blockers.size
        assert scheduler.test_blockers.first[0].is_a?(Thread) # the blocked thread that called take
        assert_equal blocked_thread, scheduler.test_blockers.first[0]
        assert_equal nil, scheduler.test_blockers.first[1] # join does not take a timeout
      end
    end;
  end

  def test_ractor_join_after_ractor_finished_in_fiber_scheduler_context
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber", require_relative: "scheduler")
    begin;
      scheduler = Scheduler.new
      class << scheduler
        attr_reader :test_blockers
        def block(blocker, timeout=nil)
          (@test_blockers ||= []) << [blocker, timeout]
          super
        end
      end
      Fiber.set_scheduler scheduler
      # in f1 (main fiber)
      Fiber.schedule do
        # in f2
        r = Ractor.new do
          # in f3
          :done
        end
        sleep 0.5 # give time for ractor to finish
        # Calling `r.join` here should not block because the ractor is already done yielding its value
        r.join
      end
      at_exit do
        assert_equal 1, scheduler.test_blockers.size
        assert_equal [:sleep, 0.5], scheduler.test_blockers.first # sleep in the fiber scheduler blocked, but not `r.join`
      end
    end;
  end

  def test_ractor_join_in_fiber_scheduler_context_fiber_killed_before_join
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber", require_relative: "scheduler")
    begin;
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler
      # in f1 (main fiber)
      ordering = []
      fiber_calling_join = nil
      r = nil
      Fiber.schedule do
        fiber_calling_join = Fiber.current
        # in f2
        r = Ractor.new do
          # in f3
          sleep 0.5
        end
        ordering << "f2 before join"
        r.join
        ordering << "f2 after join" # fiber is killed by root fiber, doesn't get here
      end
      ordering << "f1 thread finish"
      expected_ordering = ["f2 before join", "f1 thread finish"]
      fiber_calling_join.kill
      at_exit do
        assert_equal expected_ordering, ordering
      end
    end;
  end

  def test_ractor_join_in_fiber_scheduler_context_fiber_killed_before_join_cleans_up_ractor
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber", require_relative: "scheduler")
    begin;
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler
      # in f1 (main fiber)
      ordering = []
      fiber_calling_join = nil
      r = nil
      Fiber.schedule do
        fiber_calling_join = Fiber.current
        # in f2
        r = Ractor.new do
          # in f3
          sleep 0.5
          :hi
        end
        ordering << "f2 before join"
        r.join
        ordering << "f2 after join" # fiber is killed by root fiber, doesn't get here
      end
      ordering << "f1 thread finish"
      expected_ordering = ["f2 before join", "f1 thread finish"]
      fiber_calling_join.kill
      ractor_val = r.value
      at_exit do
        assert_equal expected_ordering, ordering
        assert_equal :hi, ractor_val
      end
    end;
  end

  def test_ractor_value_in_fiber_scheduler_context_not_main_thread
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber", require_relative: "scheduler")
    begin;
      ordering = []
      scheduler = nil
      Thread.new do
        # in f2
        scheduler = Scheduler.new
        class << scheduler
          attr_reader :test_blockers
          def block(blocker, timeout=nil)
            (@test_blockers ||= []) << [blocker, timeout]
            super
          end
        end
        Fiber.set_scheduler scheduler
        Fiber.schedule do
          # in f3
          r = Ractor.new do
            # in f4
            sleep 0.5
            :hi
          end
          ordering << "f3 before join"
          # Calling `r.join` should schedule us away from f3 back to f2. In f2, we end the thread
          # and then Scheduler#run is called, which blocks on IO.select. When the ractor is finished,
          # it resumes fiber f3.
          r.join
          ordering << "f3 after join"
        end
        ordering << "f2 thread finish"
      end.join
      expected_ordering = ["f3 before join", "f2 thread finish", "f3 after join"]
      assert_equal expected_ordering, ordering
      assert_equal 1, scheduler.test_blockers.size
    end;
  end

  def test_ractor_value_in_fiber_scheduler_context_not_main_thread_thread_killed
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber", require_relative: "scheduler")
    begin;
      ordering = []
      scheduler = nil
      r = nil
      Thread.new do
        # in f2
        scheduler = Scheduler.new
        class << scheduler
          attr_reader :test_blockers
          def block(blocker, timeout=nil)
            (@test_blockers ||= []) << [blocker, timeout]
            super
          end
        end
        Fiber.set_scheduler scheduler
        Fiber.schedule do
          # in f3
          r = Ractor.new do
            # in f4
            sleep 0.5
            :hi
          end
          ordering << "f3 before join"
          # Calling `r.value` should schedule us away from f3 back to f2. In f2, we end the thread
          # and then Scheduler#run is called, which blocks on IO.select. When the ractor is finished,
          # it resumes fiber f3.
          v = r.value
          ordering << "f3 after join: #{v}"
        end
        ordering << "f2 thread finish"
        Thread.current.kill
      end.join
      ordering << "th1 after join"
      expected_ordering = ["f3 before join", "f2 thread finish", "f3 after join: hi", "th1 after join"]

      val = r.value
      assert_equal :hi, val
      assert_equal expected_ordering, ordering
      assert_equal 1, scheduler.test_blockers.size
    end;
  end

  def test_ractor_value_in_fiber_scheduler_context_not_main_thread_thread_raised
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber", require_relative: "scheduler")
    begin;
      ordering = []
      scheduler = nil
      r = nil
      Thread.new do
        Thread.current.report_on_exception = false
        # in f2
        scheduler = Scheduler.new
        class << scheduler
          attr_reader :test_blockers
          def block(blocker, timeout=nil)
            (@test_blockers ||= []) << [blocker, timeout]
            super
          end
        end
        Fiber.set_scheduler scheduler
        Fiber.schedule do
          # in f3
          r = Ractor.new do
            # in f4
            sleep 0.5
            :hi
          end
          ordering << "f3 before join"
          # Calling `r.value` should schedule us away from f3 back to f2. In f2, we end the thread
          # and then Scheduler#run is called, which blocks on IO.select. When the ractor is finished,
          # it resumes fiber f3.
          v = r.value
          ordering << "f3 after join: #{v}"
        end
        ordering << "f2 thread finish"
        raise "error"
      end.join rescue RuntimeError
      ordering << "th1 after join"
      expected_ordering = ["f3 before join", "f2 thread finish", "f3 after join: hi", "th1 after join"]

      val = r.value
      assert_equal :hi, val
      assert_equal expected_ordering, ordering
      assert_equal 1, scheduler.test_blockers.size
    end;
  end

  def test_ractor_join_in_non_fiber_scheduler_context
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "fiber", require_relative: "scheduler")
    begin;
      scheduler = Scheduler.new
      class << scheduler
        attr_reader :test_blockers
        def block(blocker, timeout=nil)
          (@test_blockers ||= []) << [blocker, timeout]
          super
        end
      end
      Fiber.set_scheduler scheduler
      is_blocking = nil
      Fiber.new(blocking: true) do
        is_blocking = Fiber.current.blocking?
        r = Ractor.new do
          sleep 0.5
          :done
        end
        # Calling `r.join` here should block, NOT switch fibers (we're not in Fiber.schedule block AKA fiber scheduler context)
        r.join
      end.transfer
      at_exit do
        assert_equal true, is_blocking
        assert_equal nil, scheduler.test_blockers
      end
    end;
  end
end
