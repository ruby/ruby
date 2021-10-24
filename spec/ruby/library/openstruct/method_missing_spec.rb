require_relative '../../spec_helper'
require "ostruct"

describe "OpenStruct#method_missing when called with a method name ending in '='" do
  before :each do
    @os = OpenStruct.new
  end

  it "raises an ArgumentError when not passed any additional arguments" do
    -> { @os.send(:test=) }.should raise_error(ArgumentError)
  end
end

describe "OpenStruct#method_missing when passed additional arguments" do
  it "raises a NoMethodError when the key does not exist" do
    os = OpenStruct.new
    -> { os.test(1, 2, 3) }.should raise_error(NoMethodError)
  end

  ruby_version_is "2.7" do
    it "raises an ArgumentError when the key exists" do
      os = OpenStruct.new(test: 20)
      -> { os.test(1, 2, 3) }.should raise_error(ArgumentError)
    end
  end
end
