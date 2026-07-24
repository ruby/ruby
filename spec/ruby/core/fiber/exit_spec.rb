require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "Fiber.exit" do
    it "terminates the current fiber and transfers to the given fiber with the arguments" do
      log = []
      target = worker = nil
      target = Fiber.new do
        worker = Fiber.new do
          log << :worker
          Fiber.exit(target, :from_worker)
          log << :unreachable
        end
        log << worker.transfer
        log << worker.alive?
      end
      target.resume
      log.should == [:worker, :from_worker, false]
    end

    it "terminates the current fiber and returns to the resumer without a target" do
      log = []
      captured = nil
      fiber = Fiber.new do
        captured = Fiber.current
        Fiber.exit
        log << :unreachable
      end
      fiber.resume
      captured.alive?.should == false
      log.should == []
    end

    it "does not run ensure blocks of the exiting fiber" do
      log = []
      target = nil
      target = Fiber.new do
        worker = Fiber.new do
          begin
            Fiber.exit(target)
          ensure
            log << :ensure
          end
        end
        worker.transfer
        log << :resumed
      end
      target.resume
      log.should == [:resumed]
    end

    it "works when the current fiber was entered via resume" do
      log = []
      a = b = target = nil
      target = Fiber.new { log << :target }
      b = Fiber.new do
        log << :b
        Fiber.exit(target)
        log << :unreachable
      end
      a = Fiber.new do
        log << :a_before
        b.resume
        log << :a_after
      end
      a.resume
      log.should == [:a_before, :b, :target, :a_after]
    end

    it "transfers to the target even when it was entered via transfer" do
      result = nil
      loop_fiber = Fiber.new do
        task = Fiber.new do
          Fiber.exit(loop_fiber, :done)
        end
        result = task.transfer
      end
      loop_fiber.transfer
      result.should == :done
    end

    it "allows exiting to the current fiber's resumer" do
      log = []
      outer = nil
      outer = Fiber.new do
        inner = Fiber.new do
          log << :inner
          Fiber.exit(outer)
        end
        inner.resume
        log << :outer_after
      end
      outer.resume
      log.should == [:inner, :outer_after]
    end

    it "raises a FiberError when exiting to a fiber that is resuming another fiber" do
      root = Fiber.current
      a = Fiber.new do
        b = Fiber.new { Fiber.exit(root) }
        b.resume
      end
      -> { a.resume }.should raise_error(FiberError)
    end

    it "raises a FiberError when exiting to a yielding fiber" do
      yielding = Fiber.new { Fiber.yield }
      yielding.resume
      f = Fiber.new { Fiber.exit(yielding) }
      -> { f.resume }.should raise_error(FiberError)
    end

    it "raises a FiberError when exiting to the current fiber" do
      -> { Fiber.exit(Fiber.current) }.should raise_error(FiberError)
    end

    it "raises a FiberError when exiting to a terminated fiber" do
      dead = Fiber.new {}
      dead.resume
      f = Fiber.new { Fiber.exit(dead) }
      -> { f.resume }.should raise_error(FiberError)
    end
  end
end
