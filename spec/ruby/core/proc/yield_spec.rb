require_relative '../../spec_helper'

describe "Proc#yield" do
  it "is an alias of Proc#call" do
    Proc.instance_method(:yield).should == Proc.instance_method(:call)
  end
end
