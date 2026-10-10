require_relative '../../spec_helper'

describe "NilClass#false?" do
  it "returns false" do
    nil.false?.should == false
  end
end