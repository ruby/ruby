require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/kernel/raise'

describe "Fiber#raise" do
  it_behaves_like :kernel_raise, :raise, FiberSpecs::NewFiberToRaise
  it_behaves_like :kernel_raise_across_contexts, :raise, FiberSpecs::NewFiberToRaise
end

describe "Fiber#raise" do
  it 'raises RuntimeError by default' do
    -> { FiberSpecs::NewFiberToRaise.raise }.should raise_error(RuntimeError)
  end

  it "raises FiberError if Fiber is not born" do
    fiber = Fiber.new { true }
    -> { fiber.raise }.should raise_error(FiberError, "cannot raise exception on unborn fiber")
  end

  it "raises FiberError if Fiber is dead" do
    fiber = Fiber.new { true }
    fiber.resume
    -> { fiber.raise }.should raise_error(FiberError, /dead fiber called|attempt to resume a terminated fiber/)
  end

  it 'accepts error class' do
    -> { FiberSpecs::NewFiberToRaise.raise FiberSpecs::CustomError }.should raise_error(FiberSpecs::CustomError)
  end

  it 'accepts error message' do
    -> { FiberSpecs::NewFiberToRaise.raise "error message" }.should raise_error(RuntimeError, "error message")
  end

  it 'does not accept array of backtrace information only' do
    -> { FiberSpecs::NewFiberToRaise.raise ['foo'] }.should raise_error(TypeError)
  end

  it 'does not accept integer' do
    -> { FiberSpecs::NewFiberToRaise.raise 100 }.should raise_error(TypeError)
  end

  it 'accepts error class with error message' do
    -> { FiberSpecs::NewFiberToRaise.raise FiberSpecs::CustomError, 'test error' }.should raise_error(FiberSpecs::CustomError, 'test error')
  end

  it 'accepts error class with error message and backtrace information' do
    -> {
      FiberSpecs::NewFiberToRaise.raise FiberSpecs::CustomError, 'test error', ['foo', 'boo']
    }.should raise_error(FiberSpecs::CustomError) { |e|
      e.message.should == 'test error'
      e.backtrace.should == ['foo', 'boo']
    }
  end

  it 'does not accept only error message and backtrace information' do
    -> { FiberSpecs::NewFiberToRaise.raise 'test error', ['foo', 'boo'] }.should raise_error(TypeError)
  end

  it "raises a FiberError if invoked from a different Thread" do
    fiber = Fiber.new { Fiber.yield }
    fiber.resume
    Thread.new do
      -> {
        fiber.raise
      }.should raise_error(FiberError, "fiber called across threads")
    end.join
  end

  it "kills Fiber" do
    fiber = Fiber.new { Fiber.yield :first; :second }
    fiber.resume
    -> { fiber.raise }.should raise_error
    -> { fiber.resume }.should raise_error(FiberError, /dead fiber called|attempt to resume a terminated fiber/)
  end

  it "returns to calling fiber after raise" do
    fiber_one = Fiber.new do
      Fiber.yield :yield_one
      :unreachable
    end

    fiber_two = Fiber.new do
      results = []
      results << fiber_one.resume
      begin
        fiber_one.raise
      rescue
        results << :rescued
      end
      results
    end

    fiber_two.resume.should == [:yield_one, :rescued]
  end

  ruby_version_is "3.4" do
    it "raises on the resumed fiber" do
      root_fiber = Fiber.current
      f1 = Fiber.new { root_fiber.transfer }
      f2 = Fiber.new { f1.resume }
      f2.transfer

      -> do
        f2.raise(RuntimeError, "Expected error")
      end.should raise_error(RuntimeError, "Expected error")
    end

    it "raises on itself" do
      -> do
        Fiber.current.raise(RuntimeError, "Expected error")
      end.should raise_error(RuntimeError, "Expected error")
    end

    it "should raise on parent fiber" do
      f2 = nil
      f1 = Fiber.new do
        # This is equivalent to Kernel#raise:
        f2.raise(RuntimeError, "Expected error")
      end
      f2 = Fiber.new do
        f1.resume
      end

      -> do
        f2.resume
      end.should raise_error(RuntimeError, "Expected error")
    end
  end
end


describe "Fiber#raise" do
  it "transfers and raises on a transferring fiber" do
    root = Fiber.current
    fiber = Fiber.new { root.transfer }
    fiber.transfer
    -> { fiber.raise "msg" }.should raise_error(RuntimeError, "msg")
  end
end
