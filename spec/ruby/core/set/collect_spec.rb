require_relative '../../spec_helper'

describe "Set#collect!" do
  it "is an alias of Set#map!" do
    Set.instance_method(:collect!).should == Set.instance_method(:map!)
  end
end
