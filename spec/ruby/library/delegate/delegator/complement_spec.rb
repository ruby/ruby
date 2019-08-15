require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#~" do
  it "is delegated" do
    base = mock('base')
    delegator = DelegateSpecs::Delegator.new(base)
    base.should_receive(:~).and_return(:foo)
    (~delegator).should == :foo
  end
end
