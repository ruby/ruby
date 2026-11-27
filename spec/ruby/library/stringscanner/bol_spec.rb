require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#bol?" do
  it "is an alias of StringScanner#beginning_of_line?" do
    StringScanner.instance_method(:bol?).should == StringScanner.instance_method(:beginning_of_line?)
  end
end
