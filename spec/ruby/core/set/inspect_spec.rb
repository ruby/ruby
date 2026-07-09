require_relative '../../spec_helper'

describe "Set#inspect" do
  it "is an alias of Set#to_s" do
    Set.instance_method(:inspect).should == Set.instance_method(:to_s)
  end
end
