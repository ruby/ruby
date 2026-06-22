require_relative '../../spec_helper'

describe "Set#length" do
  it "is an alias of Set#size" do
    Set.instance_method(:length).should == Set.instance_method(:size)
  end
end
