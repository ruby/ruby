require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#unscan" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "set the scan pointer to the previous position" do
    @s.scan(/This/)
    @s.unscan
    @s.matched.should == nil
    @s.pos.should == 0
  end

  it "remember only one previous position" do
    @s.scan(/This/)
    pos = @s.pos
    @s.scan(/ is/)
    @s.unscan
    @s.pos.should == pos
  end

  it "raises a StringScanner::Error when the previous match had failed" do
    -> { @s.unscan }.should raise_error(StringScanner::Error)
    -> { @s.scan(/\d/); @s.unscan }.should raise_error(StringScanner::Error)
  end
end
