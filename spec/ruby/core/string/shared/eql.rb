# encoding: binary
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :string_eql_value, shared: true do
  it "returns true if self <=> string returns 0" do
    'hello'.send(@method, 'hello').should be_true
  end

  it "returns false if self <=> string does not return 0" do
    "more".send(@method, "MORE").should be_false
    "less".send(@method, "greater").should be_false
  end

  it "ignores encoding difference of compatible string" do
    "hello".dup.force_encoding("utf-8").send(@method, "hello".dup.force_encoding("iso-8859-1")).should be_true
  end

  it "considers encoding difference of incompatible string" do
    "\xff".dup.force_encoding("utf-8").send(@method, "\xff".dup.force_encoding("iso-8859-1")).should be_false
  end

  it "considers encoding compatibility" do
    "abcd".dup.force_encoding("utf-8").send(@method, "abcd".dup.force_encoding("utf-32le")).should be_false
  end

  it "ignores subclass differences" do
    a = "hello"
    b = StringSpecs::MyString.new("hello")

    a.send(@method, b).should be_true
    b.send(@method, a).should be_true
  end

  it "returns true when comparing 2 empty strings but one is not ASCII-compatible" do
    "".send(@method, "".dup.force_encoding('iso-2022-jp')).should == true
  end
end
