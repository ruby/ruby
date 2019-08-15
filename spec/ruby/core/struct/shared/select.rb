require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :struct_select, shared: true do
  it "raises an ArgumentError if given any non-block arguments" do
    struct = StructClasses::Car.new
    -> { struct.send(@method, 1) { } }.should raise_error(ArgumentError)
  end

  it "returns a new array of elements for which block is true" do
    struct = StructClasses::Car.new("Toyota", "Tercel", "2000")
    struct.send(@method) { |i| i == "2000" }.should == [ "2000" ]
  end

  it "returns an instance of Array" do
    struct = StructClasses::Car.new("Ford", "Escort", "1995")
    struct.send(@method) { true }.should be_an_instance_of(Array)
  end

  describe "without block" do
    it "returns an instance of Enumerator" do
      struct = Struct.new(:foo).new
      struct.send(@method).should be_an_instance_of(Enumerator)
    end
  end
end
