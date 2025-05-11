require_relative '../../spec_helper'
require 'coverage'

describe "Coverage.supported?" do
  it "returns true or false if coverage measurement is supported for the given mode" do
    [true, false].should.include?(Coverage.supported?(:lines))
    [true, false].should.include?(Coverage.supported?(:branches))
    [true, false].should.include?(Coverage.supported?(:methods))
    [true, false].should.include?(Coverage.supported?(:eval))
  end

  it "returns false for not existing modes" do
    Coverage.supported?(:foo).should == false
    Coverage.supported?(:bar).should == false
  end

  it "raise TypeError if argument is not Symbol" do
    -> {
      Coverage.supported?("lines")
    }.should raise_error(TypeError, "wrong argument type String (expected Symbol)")

    -> {
      Coverage.supported?([])
    }.should raise_error(TypeError, "wrong argument type Array (expected Symbol)")

    -> {
      Coverage.supported?(1)
    }.should raise_error(TypeError, "wrong argument type Integer (expected Symbol)")
  end
end
