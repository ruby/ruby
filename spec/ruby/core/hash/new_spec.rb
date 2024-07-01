require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash.new" do
  it "creates an empty Hash if passed no arguments" do
    Hash.new.should == {}
    Hash.new.size.should == 0
  end

  it "creates a new Hash with default object if passed a default argument" do
    Hash.new(5).default.should == 5
    Hash.new({}).default.should == {}
  end

  it "does not create a copy of the default argument" do
    str = "foo"
    Hash.new(str).default.should equal(str)
  end

  it "creates a Hash with a default_proc if passed a block" do
    Hash.new.default_proc.should == nil

    h = Hash.new { |x| "Answer to #{x}" }
    h.default_proc.call(5).should == "Answer to 5"
    h.default_proc.call("x").should == "Answer to x"
  end

  it "raises an ArgumentError if more than one argument is passed" do
    -> { Hash.new(5,6) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if passed both default argument and default block" do
    -> { Hash.new(5) { 0 }   }.should raise_error(ArgumentError)
    -> { Hash.new(nil) { 0 } }.should raise_error(ArgumentError)
  end

  ruby_version_is "3.3"..."3.4" do
    it "emits a deprecation warning if keyword arguments are passed" do
      -> { Hash.new(unknown: true) }.should complain(
        Regexp.new(Regexp.escape("Calling Hash.new with keyword arguments is deprecated and will be removed in Ruby 3.4; use Hash.new({ key: value }) instead"))
      )

      -> { Hash.new(1, unknown: true) }.should raise_error(ArgumentError)
      -> { Hash.new(unknown: true) { 0 } }.should raise_error(ArgumentError)

      Hash.new({ unknown: true }).default.should == { unknown: true }
    end
  end

  ruby_version_is "3.4" do
    it "accepts a capacity: argument" do
      Hash.new(5, capacity: 42).default.should == 5
      Hash.new(capacity: 42).default.should == nil
      (Hash.new(capacity: 42) { 1 }).default_proc.should_not == nil
    end

    it "ignores negative capacity" do
      -> { Hash.new(capacity: -42) }.should_not raise_error
    end

    it "raises an error if unknown keyword arguments are passed" do
      -> { Hash.new(unknown: true) }.should raise_error(ArgumentError)
      -> { Hash.new(1, unknown: true) }.should raise_error(ArgumentError)
      -> { Hash.new(unknown: true) { 0 } }.should raise_error(ArgumentError)
    end
  end
end
