require_relative '../../spec_helper'

describe "Marshal::MINOR_VERSION" do
  it "is 8" do
    Marshal::MINOR_VERSION.should == 8
  end
end
