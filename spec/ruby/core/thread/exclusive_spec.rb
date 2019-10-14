require_relative '../../spec_helper'

describe "Thread.exclusive" do
  verbose = Object

  before :each do
    ScratchPad.clear
    verbose, $VERBOSE = $VERBOSE, nil
  end

  after :each do
    $VERBOSE = verbose
  end

  it "yields to the block" do
    Thread.exclusive { ScratchPad.record true }
    ScratchPad.recorded.should == true
  end

  it "returns the result of yielding" do
    Thread.exclusive { :result }.should == :result
  end

  it "blocks the caller if another thread is also in an exclusive block" do
    m = Mutex.new
    q1 = Queue.new
    q2 = Queue.new

    t = Thread.new {
      Thread.exclusive {
        q1.push :ready
        q2.pop
      }
    }

    q1.pop.should == :ready

    -> { Thread.exclusive { } }.should block_caller

    q2.push :done
    t.join
  end

  it "is not recursive" do
    Thread.exclusive do
      -> { Thread.exclusive { } }.should raise_error(ThreadError)
    end
  end
end
