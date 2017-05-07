require File.expand_path('../../../spec_helper', __FILE__)

describe "Bignum" do
  it "includes Comparable" do
    Bignum.include?(Comparable).should == true
  end
end
