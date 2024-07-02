require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#scan_until" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the substring up to and including the end of the match" do
    @s.scan_until(/a/).should == "This is a"
    @s.pre_match.should == "This is "
    @s.post_match.should == " test"
  end

  it "returns nil if there's no match" do
    @s.scan_until(/\d/).should == nil
  end

  it "can match anchors properly" do
    @s.scan(/T/)
    @s.scan_until(/^h/).should == "h"
  end

  it "raises TypeError if given a String" do
    -> {
      @s.scan_until('T')
    }.should raise_error(TypeError, 'wrong argument type String (expected Regexp)')
  end
end
