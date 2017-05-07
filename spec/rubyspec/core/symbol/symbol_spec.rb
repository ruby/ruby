require File.expand_path('../../../spec_helper', __FILE__)

describe "Symbol" do
  it "includes Comparable" do
    Symbol.include?(Comparable).should == true
  end
end
