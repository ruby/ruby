require_relative '../../spec_helper'
require 'ostruct'
require_relative 'fixtures/classes'

describe "OpenStruct#to_s" do
  it "returns a String representation of self" do
    os = OpenStruct.new(name: "John Smith")
    os.to_s.should == "#<OpenStruct name=\"John Smith\">"

    os = OpenStruct.new(age: 20, name: "John Smith")
    os.to_s.should.is_a?(String)
  end

  it "correctly handles self-referential OpenStructs" do
    os = OpenStruct.new
    os.self = os
    os.to_s.should == "#<OpenStruct self=#<OpenStruct ...>>"
  end

  it "correctly handles OpenStruct subclasses" do
    os = OpenStructSpecs::OpenStructSub.new(name: "John Smith")
    os.to_s.should == "#<OpenStructSpecs::OpenStructSub name=\"John Smith\">"
  end
end
