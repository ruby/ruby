require_relative '../../../spec_helper'
require 'rexml/document'

describe "REXML::Node#parent?" do
  it "returns true for Elements" do
    e = REXML::Element.new("foo")
    e.parent?.should == true
  end

  it "returns true for Documents" do
    e = REXML::Document.new
    e.parent?.should == true
  end

  # This includes attributes, CDatas and declarations.
  it "returns false for Texts" do
    e = REXML::Text.new("foo")
    e.parent?.should == false
  end
end
