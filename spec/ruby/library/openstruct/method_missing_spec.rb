require_relative '../../spec_helper'
require "ostruct"

describe "OpenStruct#method_missing when called with a method name ending in '='" do
  before :each do
    @os = OpenStruct.new
  end

  it "raises an ArgumentError when not passed any additional arguments" do
    -> { @os.method_missing(:test=) }.should raise_error(ArgumentError)
  end

  it "raises a TypeError when self is frozen" do
    @os.freeze
    -> { @os.method_missing(:test=, "test") }.should raise_error(RuntimeError)
  end

  it "creates accessor methods" do
    @os.method_missing(:test=, "test")
    @os.respond_to?(:test=).should be_true
    @os.respond_to?(:test).should be_true

    @os.test.should == "test"
    @os.test = "changed"
    @os.test.should == "changed"
  end
end

describe "OpenStruct#method_missing when passed additional arguments" do
  it "raises a NoMethodError when the key does not exist" do
    os = OpenStruct.new
    -> { os.method_missing(:test, 1, 2, 3) }.should raise_error(NoMethodError)
  end

  ruby_version_is "2.7" do
    it "raises an ArgumentError when the key exists" do
      os = OpenStruct.new(test: 20)
      -> { os.method_missing(:test, 1, 2, 3) }.should raise_error(ArgumentError)
    end
  end
end

describe "OpenStruct#method_missing when not passed any additional arguments" do
  it "returns the value for the passed method from the method/value table" do
    os = OpenStruct.new(age: 20)
    os.method_missing(:age).should eql(20)
    os.method_missing(:name).should be_nil
  end
end
