require_relative '../../spec_helper'

describe "Enumerator#next" do
  before :each do
    @enum = 1.upto(3)
  end

  it "returns the next element of the enumeration" do
    @enum.next.should == 1
    @enum.next.should == 2
    @enum.next.should == 3
  end

  it "raises a StopIteration exception at the end of the stream" do
    3.times { @enum.next }
    -> { @enum.next }.should raise_error(StopIteration)
  end

  it "cannot be called again until the enumerator is rewound" do
    3.times { @enum.next }
    -> { @enum.next }.should raise_error(StopIteration)
    -> { @enum.next }.should raise_error(StopIteration)
    -> { @enum.next }.should raise_error(StopIteration)
    @enum.rewind
    @enum.next.should == 1
  end

  it "restarts the enumerator if an exception terminated a previous iteration" do
    exception = StandardError.new
    enum = Enumerator.new do
      raise exception
    end

    result = 2.times.map { enum.next rescue $! }

    result.should == [exception, exception]
  end
end
