require_relative "../../spec_helper"

describe "Numeric#magnitude" do
  it "is an alias of Numeric#abs" do
    Numeric.instance_method(:magnitude).should == Numeric.instance_method(:abs)
  end
end
