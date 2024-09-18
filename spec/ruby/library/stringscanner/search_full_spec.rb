require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#search_full" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the number of bytes advanced" do
    orig_pos = @s.pos
    @s.search_full(/This/, false, false).should == 4
    @s.pos.should == orig_pos
  end

  it "returns the number of bytes advanced and advances the scan pointer if the second argument is true" do
    @s.search_full(/This/, true, false).should == 4
    @s.pos.should == 4
  end

  it "returns the matched string if the third argument is true" do
    orig_pos = @s.pos
    @s.search_full(/This/, false, true).should == "This"
    @s.pos.should == orig_pos
  end

  it "returns the matched string if the third argument is true and advances the scan pointer if the second argument is true" do
    @s.search_full(/This/, true, true).should == "This"
    @s.pos.should == 4
  end

  ruby_version_is ""..."3.4" do
    it "raises TypeError if given a String" do
      -> {
        @s.search_full('T', true, true)
      }.should raise_error(TypeError, 'wrong argument type String (expected Regexp)')
    end
  end
end
