require_relative '../../spec_helper'
require "stringio"

describe "StringIO#inspect" do
  it "returns the same as #to_s" do
    io = StringIO.new("example")
    io.inspect.should == io.to_s
  end

  it "does not include the contents" do
    io = StringIO.new("contents")
    io.inspect.should_not include("contents")
  end

  it "uses the regular Object#inspect without any instance variable" do
    io = StringIO.new("example")
    io.inspect.should =~ /\A#<StringIO:0x\h+>\z/
  end
end
