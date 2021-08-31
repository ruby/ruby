require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread#[]=" do
  after :each do
    Thread.current[:value] = nil
  end

  it "raises a FrozenError if the thread is frozen" do
    Thread.new do
      th = Thread.current
      th.freeze
      -> {
        th[:foo] = "bar"
      }.should raise_error(FrozenError, /frozen/)
    end.join
  end

  it "raises exceptions on the wrong type of keys" do
    -> { Thread.current[nil] = true }.should raise_error(TypeError)
    -> { Thread.current[5] = true }.should raise_error(TypeError)
  end

  it "is not shared across fibers" do
    fib = Fiber.new do
      Thread.current[:value] = 1
      Fiber.yield
      Thread.current[:value].should == 1
    end
    fib.resume
    Thread.current[:value].should be_nil
    Thread.current[:value] = 2
    fib.resume
    Thread.current[:value] = 2
  end

  it "stores a local in another thread when in a fiber" do
    fib = Fiber.new do
      t = Thread.new do
        sleep
        Thread.current[:value].should == 1
      end

      Thread.pass while t.status and t.status != "sleep"
      t[:value] = 1
      t.wakeup
      t.join
    end
    fib.resume
  end
end
