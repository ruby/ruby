require_relative '../../../spec_helper'

describe "Enumerator::Chain#inspect" do
  it "shows a representation of the Enumerator" do
    Enumerator::Chain.new.inspect.should == "#<Enumerator::Chain: []>"
    Enumerator::Chain.new(1..2, 3..4).inspect.should == "#<Enumerator::Chain: [1..2, 3..4]>"
  end

  it "calls inspect on its chain elements" do
    obj = mock('inspect')
    obj.should_receive(:inspect).and_return('some desc')
    Enumerator::Chain.new(obj).inspect.should == "#<Enumerator::Chain: [some desc]>"
  end

  it "returns a not initialized representation if #initialized is not called yet" do
    Enumerator::Chain.allocate.inspect.should == "#<Enumerator::Chain: uninitialized>"
  end
end
