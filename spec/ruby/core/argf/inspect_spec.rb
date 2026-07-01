require_relative '../../spec_helper'

describe "ARGF.inspect" do
  it "is an alias of ARGF.to_s" do
    ARGF.method(:inspect).should == ARGF.method(:to_s)
  end
end
