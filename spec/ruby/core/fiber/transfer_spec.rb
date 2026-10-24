require_relative '../../spec_helper'
require_relative 'shared/resume'

describe "Fiber#transfer" do
  it_behaves_like :fiber_resume, :transfer
end

describe "Fiber#transfer" do
  it "transfers control from one Fiber to another when called from a Fiber" do
    fiber1 = Fiber.new { :fiber1 }
    fiber2 = Fiber.new { fiber1.transfer; :fiber2 }
    fiber2.resume.should == :fiber2
  end

  ruby_version_is ""..."4.1" do
    it "returns to the root Fiber when finished" do
      f1 = Fiber.new { :fiber_1 }
      f2 = Fiber.new { f1.transfer; :fiber_2 }

      f2.transfer.should == :fiber_1
      f2.transfer.should == :fiber_2
    end
  end

  ruby_version_is "4.1" do
    it "returns to the transferring Fiber when finished" do
      states = []
      f1 = Fiber.new { states << :f1 }
      f2 = Fiber.new { f1.transfer; states << :f2 }

      f2.transfer
      states.should == [:f1, :f2]
    end

    it "unwinds to the most recent transferring Fiber when finished" do
      states = []
      a = b = nil
      a = Fiber.new { states << :a1; b.transfer; states << :a2 }
      b = Fiber.new { states << :b1; a.transfer; states << :b2 }

      a.transfer
      states.should == [:a1, :b1, :a2, :b2]
    end

    it "does not clobber the resume caller when a resumed Fiber transfers and is transferred back" do
      states = []
      a = b = nil
      a = Fiber.new { states << :a_start; b.transfer; states << :a_resumed; Fiber.yield; states << :a_after_yield }
      b = Fiber.new { states << :b_start; a.transfer; states << :b_never }

      a.resume
      states << :back_in_caller
      a.resume
      states.should == [:a_start, :b_start, :a_resumed, :back_in_caller, :a_after_yield]
    end
  end

  it "can be invoked from the same Fiber it transfers control to" do
    states = []
    fiber = Fiber.new { states << :start; fiber.transfer; states << :end }
    fiber.transfer
    states.should == [:start, :end]

    states = []
    fiber = Fiber.new { states << :start; fiber.transfer; states << :end }
    fiber.resume
    states.should == [:start, :end]
  end

  it "can not transfer control to a Fiber that has suspended by Fiber.yield" do
    states = []
    fiber1 = Fiber.new { states << :fiber1 }
    fiber2 = Fiber.new { states << :fiber2_start; Fiber.yield fiber1.transfer; states << :fiber2_end}
    fiber2.resume.should == [:fiber2_start, :fiber1]
    -> { fiber2.transfer }.should.raise(FiberError)
  end

  it "raises a FiberError when transferring to a Fiber which resumes itself" do
    fiber = Fiber.new { fiber.resume }
    -> { fiber.transfer }.should.raise(FiberError)
  end

  it "works if Fibers in different Threads each transfer to a Fiber in the same Thread" do
    # This catches a bug where Fibers are running on a thread-pool
    # and Fibers from a different Ruby Thread reuse the same native thread.
    # Caching the Ruby Thread based on the native thread is not correct in that case,
    # and the check for "fiber called across threads" in Fiber#transfer
    # might be incorrect based on that.
    2.times do
      Thread.new do
        io_fiber = Fiber.new do |calling_fiber|
          calling_fiber.transfer
        end
        io_fiber.transfer(Fiber.current)
        value = Object.new
        io_fiber.transfer(value).should.equal? value
      end.join
    end
  end

  it "transfers control between a non-main thread's root fiber to a child fiber and back again" do
    states = []
    thread = Thread.new do
      f1 = Fiber.new do |f0|
        states << 0
        value2 = f0.transfer(1)
        states << value2
        3
      end

      value1 = f1.transfer(Fiber.current)
      states << value1
      value3 = f1.transfer(2)
      states << value3
    end
    thread.join
    states.should == [0, 1, 2, 3]
  end
end
