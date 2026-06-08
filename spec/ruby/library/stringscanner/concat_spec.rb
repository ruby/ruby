require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#concat" do
  it "is an alias of StringScanner#<<" do
    StringScanner.instance_method(:concat).should == StringScanner.instance_method(:<<)
  end
end
