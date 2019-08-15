# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

describe "String#b" do
  it "returns a binary encoded string" do
    "Hello".b.should == "Hello".force_encoding(Encoding::BINARY)
    "こんちには".b.should == "こんちには".force_encoding(Encoding::BINARY)
  end

  it "returns new string without modifying self" do
    str = "こんちには"
    str.b.should_not equal(str)
    str.should == "こんちには"
  end

  it "copies own tainted/untrusted status to the returning value" do
    utf_8 = "こんちには".taint.untrust
    ret = utf_8.b
    ret.tainted?.should be_true
    ret.untrusted?.should be_true
  end
end
