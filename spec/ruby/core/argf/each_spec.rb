require_relative '../../spec_helper'

describe "ARGF.each" do
  it "is an alias of ARGF.each_line" do
    ARGF.method(:each).should == ARGF.method(:each_line)
  end
end
