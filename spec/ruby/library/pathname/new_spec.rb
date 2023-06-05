require_relative '../../spec_helper'
require 'pathname'

describe "Pathname.new" do
  it "returns a new Pathname Object with 1 argument" do
    Pathname.new('').should be_kind_of(Pathname)
  end

  it "raises an ArgumentError when called with \0" do
    -> { Pathname.new("\0")}.should raise_error(ArgumentError)
  end

  it "raises a TypeError if not passed a String type" do
    -> { Pathname.new(nil)   }.should raise_error(TypeError)
    -> { Pathname.new(0)     }.should raise_error(TypeError)
    -> { Pathname.new(true)  }.should raise_error(TypeError)
    -> { Pathname.new(false) }.should raise_error(TypeError)
  end

  it "initializes with an object with to_path" do
    Pathname.new(mock_to_path('foo')).should == Pathname.new('foo')
  end
end
