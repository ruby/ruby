require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#size" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the number of captures groups of the last match" do
    @s.scan(/(.)(.)(.)/)
    @s.size.should == 4
  end

  it "returns nil if there is no last match" do
    @s.size.should == nil
  end
end
