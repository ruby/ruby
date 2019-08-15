require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#hash" do
  it "is delegated" do
    base = mock('base')
    delegator = DelegateSpecs::Delegator.new(base)
    base.should_receive(:hash).and_return(42)
    delegator.hash.should == 42
  end
end
