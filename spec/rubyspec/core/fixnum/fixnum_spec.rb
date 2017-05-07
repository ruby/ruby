require File.expand_path('../../../spec_helper', __FILE__)

describe "Fixnum" do
  it "includes Comparable" do
    Fixnum.include?(Comparable).should == true
  end
end
