require_relative '../../spec_helper'

describe "Marshal::MAJOR_VERSION" do
  it "is 4" do
    Marshal::MAJOR_VERSION.should == 4
  end
end
