require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#size" do
  it "is an alias of StringIO#length" do
    StringIO.instance_method(:size).should == StringIO.instance_method(:length)
  end
end
