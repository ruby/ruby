require File.expand_path('../../../spec_helper', __FILE__)

describe "Integer" do
  it "includes Comparable" do
    Integer.include?(Comparable).should == true
  end

  ruby_version_is "2.4" do
    it "is the class of both small and large integers" do
      42.class.should equal(Integer)
      bignum_value.class.should equal(Integer)
    end
  end
end

describe "Integer#integer?" do
  it "returns true for Integers" do
    0.integer?.should == true
    -1.integer?.should == true
    bignum_value.integer?.should == true
  end
end
