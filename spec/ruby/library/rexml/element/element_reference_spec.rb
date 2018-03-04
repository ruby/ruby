require 'rexml/document'
require_relative '../../../spec_helper'

describe "REXML::Element#[]" do

  before :each do
    @doc = REXML::Document.new("<root foo='bar'></root>")
    @child = REXML::Element.new("child")
    @doc.root.add_element @child
  end

  ruby_version_is "2.4" do
    it "return attribute value if argument is string or symbol" do
      @doc.root[:foo].should == 'bar'
      @doc.root['foo'].should == 'bar'
    end

    it "return nth element if argument is int" do
      @doc.root[0].should == @child
    end
  end
end
