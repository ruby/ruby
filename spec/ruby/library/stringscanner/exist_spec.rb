require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#exist?" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the index of the first occurrence of the given pattern" do
    @s.exist?(/s/).should == 4
    @s.scan(/This is/)
    @s.exist?(/s/).should == 6
  end

  it "returns 0 if the pattern is empty" do
    @s.exist?(//).should == 0
  end

  it "returns nil if the pattern isn't found in the string" do
    @s.exist?(/S/).should == nil
    @s.scan(/This is/)
    @s.exist?(/i/).should == nil
  end

  ruby_version_is ""..."3.4" do
    it "raises TypeError if given a String" do
      -> {
        @s.exist?('T')
      }.should raise_error(TypeError, 'wrong argument type String (expected Regexp)')
    end
  end
end
