require_relative '../../spec_helper'

describe "Set#<<" do
  it "is an alias of Set#add" do
    Set.instance_method(:<<).should == Set.instance_method(:add)
  end
end
