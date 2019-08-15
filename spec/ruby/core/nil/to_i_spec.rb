require_relative '../../spec_helper'

describe "NilClass#to_i" do
  it "returns 0" do
    nil.to_i.should == 0
  end

  it "does not cause NilClass to be coerced to Fixnum" do
    (0 == nil).should == false
  end
end
