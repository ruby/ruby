require_relative '../../spec_helper'

describe "Mutex#lock" do
  before :each do
    ScratchPad.clear
  end

  it "returns self" do
    m = Mutex.new
    m.lock.should == m
    m.unlock
  end

  it "waits if the lock is not available" do
    m = Mutex.new

    m.lock

    th = Thread.new do
      m.lock
      ScratchPad.record :after_lock
    end

    Thread.pass while th.status and th.status != "sleep"

    ScratchPad.recorded.should be_nil
    m.unlock
    th.join
    ScratchPad.recorded.should == :after_lock
  end

  # Unable to find a specific ticket but behavior change may be
  # related to this ML thread.
  it "raises a ThreadError when used recursively" do
    m = Mutex.new
    m.lock
    -> {
      m.lock
    }.should raise_error(ThreadError)
  end
end
