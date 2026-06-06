require_relative '../../spec_helper'

describe "Kernel#format" do
  it "is an alias of Kernel#sprintf" do
    Kernel.instance_method(:format).should == Kernel.instance_method(:sprintf)
  end
end

describe "Kernel.format" do
  it "is an alias of Kernel.sprintf" do
    Kernel.method(:format).should == Kernel.method(:sprintf)
  end
end
