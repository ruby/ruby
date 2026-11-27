require_relative '../../spec_helper'

describe "Set#filter!" do
  it "is an alias of Set#select!" do
    Set.instance_method(:filter!).should == Set.instance_method(:select!)
  end
end
