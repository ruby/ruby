require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#tell" do
  it "is an alias of StringIO#pos" do
    StringIO.instance_method(:tell).should == StringIO.instance_method(:pos)
  end
end
