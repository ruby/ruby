require_relative '../../spec_helper'

describe "Kernel#enum_for" do
  it "is an alias of Kernel#to_enum" do
    Kernel.instance_method(:enum_for).should == Kernel.instance_method(:to_enum)
  end
end
