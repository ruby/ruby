require_relative '../../spec_helper'

describe "ARGF.tell" do
  it "is an alias of ARGF.pos" do
    ARGF.method(:tell).should == ARGF.method(:pos)
  end
end
