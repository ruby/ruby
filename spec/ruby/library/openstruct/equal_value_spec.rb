require_relative '../../spec_helper'
require 'ostruct'
require_relative 'fixtures/classes'

describe "OpenStruct#==" do
  before :each do
    @os = OpenStruct.new(name: "John")
  end

  it "returns false when the passed argument is no OpenStruct" do
    (@os == Object.new).should == false
    (@os == "Test").should == false
    (@os == 10).should == false
    (@os == :sym).should == false
  end

  it "returns true when self and other are equal method/value wise" do
    (@os == @os).should == true
    (@os == OpenStruct.new(name: "John")).should == true
    (@os == OpenStructSpecs::OpenStructSub.new(name: "John")).should == true

    (@os == OpenStruct.new(name: "Jonny")).should == false
    (@os == OpenStructSpecs::OpenStructSub.new(name: "Jonny")).should == false

    (@os == OpenStruct.new(name: "John", age: 20)).should == false
    (@os == OpenStructSpecs::OpenStructSub.new(name: "John", age: 20)).should == false
  end
end
