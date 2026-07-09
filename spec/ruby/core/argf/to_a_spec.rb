require_relative '../../spec_helper'

describe "ARGF.to_a" do
  it "is an alias of ARGF.readlines" do
    ARGF.method(:to_a).should == ARGF.method(:readlines)
  end
end
