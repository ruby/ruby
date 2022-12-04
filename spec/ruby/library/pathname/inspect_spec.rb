require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#inspect" do
  it "returns a consistent String" do
    result = Pathname.new('/tmp').inspect
    result.should be_an_instance_of(String)
    result.should == "#<Pathname:/tmp>"
  end
end
