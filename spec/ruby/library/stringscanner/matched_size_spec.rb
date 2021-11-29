require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#matched_size" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the size of the most recent match" do
    @s.check(/This/)
    @s.matched_size.should == 4
    @s.matched_size.should == 4
    @s.scan(//)
    @s.matched_size.should == 0
  end

  it "returns nil if there was no recent match" do
    @s.matched_size.should == nil
    @s.check(/\d+/)
    @s.matched_size.should == nil
    @s.terminate
    @s.matched_size.should == nil
  end
end
