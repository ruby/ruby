require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#beginning_of_line?" do
  it "returns true if the scan pointer is at the beginning of the line, false otherwise" do
    s = StringScanner.new("This is a test")
    s.beginning_of_line?.should == true
    s.scan(/This/)
    s.beginning_of_line?.should == false
    s.terminate
    s.beginning_of_line?.should == false

    s = StringScanner.new("hello\nworld")
    s.beginning_of_line?.should == true
    s.scan(/\w+/)
    s.beginning_of_line?.should == false
    s.scan(/\n/)
    s.beginning_of_line?.should == true
    s.unscan
    s.beginning_of_line?.should == false
  end

  it "returns true if the scan pointer is at the end of the line of an empty string." do
    s = StringScanner.new('')
    s.terminate
    s.beginning_of_line?.should == true
  end
end
