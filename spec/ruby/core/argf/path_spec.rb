require_relative '../../spec_helper'

describe "ARGF.path" do
  it "is an alias of ARGF.filename" do
    ARGF.method(:path).should == ARGF.method(:filename)
  end
end
