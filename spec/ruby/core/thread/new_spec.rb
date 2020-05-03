require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread.new" do
  it "creates a thread executing the given block" do
    q = Queue.new
    Thread.new { q << true }.join
    q << false
    q.pop.should == true
  end

  it "can pass arguments to the thread block" do
    arr = []
    a, b, c = 1, 2, 3
    t = Thread.new(a,b,c) {|d,e,f| arr << d << e << f }
    t.join
    arr.should == [a,b,c]
  end

  it "raises an exception when not given a block" do
    -> { Thread.new }.should raise_error(ThreadError)
  end

  it "creates a subclass of thread calls super with a block in initialize" do
    arr = []
    t = ThreadSpecs::SubThread.new(arr)
    t.join
    arr.should == [1]
  end

  it "calls #initialize and raises an error if super not used" do
    c = Class.new(Thread) do
      def initialize
      end
    end

    -> {
      c.new
    }.should raise_error(ThreadError)
  end

  it "calls and respects #initialize for the block to use" do
    c = Class.new(Thread) do
      def initialize
        ScratchPad.record [:good]
        super { ScratchPad << :in_thread }
      end
    end

    t = c.new
    t.join

    ScratchPad.recorded.should == [:good, :in_thread]
  end

  it "releases Mutexes held by the Thread when the Thread finishes" do
    m1 = Mutex.new
    m2 = Mutex.new
    t = Thread.new {
      m1.lock
      m1.should.locked?
      m2.lock
      m2.should.locked?
    }
    t.join
    m1.should_not.locked?
    m2.should_not.locked?
  end

  it "releases Mutexes held by the Thread when the Thread finishes, also with Mutex#synchronize" do
    m = Mutex.new
    t = Thread.new {
      m.synchronize {
        m.unlock
        m.lock
      }
      m.lock
      m.should.locked?
    }
    t.join
    m.should_not.locked?
  end
end
