require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#tap" do
  it "yield the delegator object" do
    obj = mock('base')
    delegator = DelegateSpecs::Delegator.new(obj)
    obj.should_not_receive(:tap)
    yielded = []
    delegator.tap do |x|
      yielded << x
    end
    yielded.size.should == 1
    yielded[0].equal?(delegator).should be_true
  end
end
