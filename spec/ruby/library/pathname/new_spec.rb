require_relative '../../spec_helper'
require 'pathname'

describe "Pathname.new" do
  it "returns a new Pathname Object with 1 argument" do
    Pathname.new('').should.is_a?(Pathname)
  end

  it "raises an ArgumentError when called with \0" do
    -> { Pathname.new("\0")}.should.raise(ArgumentError)
  end

  it "raises a TypeError if not passed a String type" do
    -> { Pathname.new(nil)   }.should.raise(TypeError)
    -> { Pathname.new(0)     }.should.raise(TypeError)
    -> { Pathname.new(true)  }.should.raise(TypeError)
    -> { Pathname.new(false) }.should.raise(TypeError)
  end

  it "initializes with an object with to_path" do
    Pathname.new(mock_to_path('foo')).should == Pathname.new('foo')
  end
end
