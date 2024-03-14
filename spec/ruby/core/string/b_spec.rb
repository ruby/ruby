# -*- encoding: utf-8 -*-
# frozen_string_literal: false
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
end
