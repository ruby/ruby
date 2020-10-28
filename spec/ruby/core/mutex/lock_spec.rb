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

  it "blocks the caller if already locked" do
    m = Mutex.new
    m.lock
    -> { m.lock }.should block_caller
  end

  it "does not block the caller if not locked" do
    m = Mutex.new
    -> { m.lock }.should_not block_caller
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
