require_relative '../../spec_helper'

describe "Kernel#fail" do
  it "is an alias of Kernel#raise" do
    Kernel.instance_method(:fail).should == Kernel.instance_method(:raise)
  end
end

describe "Kernel.fail" do
  it "is an alias of Kernel.raise" do
    Kernel.method(:fail).should == Kernel.method(:raise)
  end
end
