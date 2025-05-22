require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#skip" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns length of the match" do
    @s.skip(/\w+/).should == 4
    @s.skip(/\s+\w+/).should == 3
  end

  it "returns nil if there's no match" do
    @s.skip(/\s+/).should == nil
    @s.skip(/\d+/).should == nil
  end

  describe "#[] successive call with a capture group name" do
    it "returns matched substring when matching succeeded" do
      @s.skip(/(?<a>This)/)
      @s.should.matched?
      @s[:a].should == "This"
    end

    it "returns nil when matching failed" do
      @s.skip(/(?<a>2008)/)
      @s.should_not.matched?
      @s[:a].should be_nil
    end
  end
end
