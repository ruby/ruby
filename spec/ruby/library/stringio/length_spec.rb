require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#length" do
  it "returns the length of the wrapped string" do
    StringIO.new("example").length.should == 7
  end
end
