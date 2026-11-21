require_relative '../../spec_helper'

describe "Numeric#conj" do
  it "is an alias of Numeric#conjugate" do
    Numeric.instance_method(:conj).should == Numeric.instance_method(:conjugate)
  end
end
