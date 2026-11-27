require_relative '../../spec_helper'

describe "Proc#inspect" do
  it "is an alias of Proc#to_s" do
    Proc.instance_method(:inspect).should == Proc.instance_method(:to_s)
  end
end
