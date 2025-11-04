require_relative '../../spec_helper'
require_relative 'shared/extract_range_matched'
require 'strscan'

describe "StringScanner#rest" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the rest of the string" do
    @s.scan(/This\s+/)
    @s.rest.should == "is a test"
  end

  it "returns self in the reset position" do
    @s.reset
    @s.rest.should == @s.string
  end

  it "returns an empty string in the terminate position" do
    @s.terminate
    @s.rest.should == ""
  end

  it_behaves_like :extract_range_matched, :rest

end
