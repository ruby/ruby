require_relative '../../spec_helper'

describe "Set#difference" do
  it "is an alias of Set#-" do
    Set.instance_method(:difference).should == Set.instance_method(:-)
  end
end
