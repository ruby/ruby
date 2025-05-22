require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#match?" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the length of the match and the scan pointer is not advanced" do
    @s.match?(/\w+/).should == 4
    @s.match?(/\w+/).should == 4
    @s.pos.should == 0
  end

  it "returns nil if there's no match" do
    @s.match?(/\d+/).should == nil
    @s.match?(/\s+/).should == nil
  end

  it "sets the last match result" do
    @s.pos = 8
    @s.match?(/a/)

    @s.pre_match.should == "This is "
    @s.matched.should == "a"
    @s.post_match.should == " test"
  end

  it "effects pre_match" do
    @s.scan(/\w+/)
    @s.scan(/\s/)

    @s.pre_match.should == "This"
    @s.match?(/\w+/)
    @s.pre_match.should == "This "
  end

  describe "#[] successive call with a capture group name" do
    it "returns matched substring when matching succeeded" do
      @s.match?(/(?<a>This)/)
      @s.should.matched?
      @s[:a].should == "This"
    end

    it "returns nil when matching failed" do
      @s.match?(/(?<a>2008)/)
      @s.should_not.matched?
      @s[:a].should be_nil
    end
  end
end
