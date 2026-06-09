require_relative '../../spec_helper'

describe "Thread.start" do
  before :each do
    ScratchPad.clear
  end

  it "raises an ArgumentError if not passed a block" do
    -> {
      Thread.start
    }.should.raise(ArgumentError)
  end

  it "spawns a new Thread running the block" do
    run = false
    t = Thread.start { run = true }
    t.should.is_a?(Thread)
    t.join

    run.should == true
  end

  it "respects Thread subclasses" do
    c = Class.new(Thread)
    t = c.start { }
    t.should.is_a?(c)

    t.join
  end

  it "does not call #initialize" do
    c = Class.new(Thread) do
      def initialize
        ScratchPad.record :bad
      end
    end

    t = c.start { }
    t.join

    ScratchPad.recorded.should == nil
  end
end
