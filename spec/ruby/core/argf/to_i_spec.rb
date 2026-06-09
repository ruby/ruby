require_relative '../../spec_helper'

describe "ARGF.to_i" do
  it "is an alias of ARGF.fileno" do
    ARGF.method(:to_i).should == ARGF.method(:fileno)
  end
end
