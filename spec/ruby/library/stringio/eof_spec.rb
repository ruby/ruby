require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#eof?" do
  before :each do
    @io = StringIO.new("eof")
  end

  it "returns true when self's position is greater than or equal to self's size" do
    @io.pos = 3
    @io.eof?.should == true

    @io.pos = 6
    @io.eof?.should == true
  end

  it "returns false when self's position is less than self's size" do
    @io.pos = 0
    @io.eof?.should == false

    @io.pos = 1
    @io.eof?.should == false

    @io.pos = 2
    @io.eof?.should == false
  end
end

describe "StringIO#eof" do
  it "is an alias of StringIO#eof?" do
    StringIO.instance_method(:eof).should == StringIO.instance_method(:eof?)
  end
end
