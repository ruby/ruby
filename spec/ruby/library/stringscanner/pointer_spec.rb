require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#pointer" do
  it "is an alias of StringScanner#pos" do
    StringScanner.instance_method(:pointer).should == StringScanner.instance_method(:pos)
  end
end

describe "StringScanner#pointer=" do
  it "is an alias of StringScanner#pos=" do
    StringScanner.instance_method(:pointer=).should == StringScanner.instance_method(:pos=)
  end
end
