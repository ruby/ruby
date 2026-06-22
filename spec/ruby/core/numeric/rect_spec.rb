require_relative '../../spec_helper'

describe "Numeric#rect" do
  it "is an alias of Numeric#rectangular" do
    Numeric.instance_method(:rect).should == Numeric.instance_method(:rectangular)
  end
end
