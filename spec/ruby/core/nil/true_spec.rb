require_relative '../../spec_helper'

describe "NilClass#true?" do
  it "returns false" do
    nil.true?.should == false
  end
end
