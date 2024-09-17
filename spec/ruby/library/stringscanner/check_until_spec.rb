require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#check_until" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the same value of scan_until, but don't advances the scan pointer" do
    @s.check_until(/a/).should == "This is a"
    @s.pos.should == 0
    @s.matched.should == "a"
    @s.check_until(/test/).should == "This is a test"
  end

  ruby_version_is ""..."3.4" do
    it "raises TypeError if given a String" do
      -> {
        @s.check_until('T')
      }.should raise_error(TypeError, 'wrong argument type String (expected Regexp)')
    end
  end
end
