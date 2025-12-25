require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#rest_size" do
  before :each do
    @s = StringScanner.new('This is a test')
  end

  it "returns the length of the rest of the string" do
    @s.rest_size.should == 14
    @s.scan(/This/)
    @s.rest_size.should == 10
    @s.terminate
    @s.rest_size.should == 0
  end

  it "is equivalent to rest.size" do
    @s.scan(/This/)
    @s.rest_size.should == @s.rest.size
  end
end
