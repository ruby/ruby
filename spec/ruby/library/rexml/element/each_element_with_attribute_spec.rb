require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Element#each_element_with_attributes" do
    before :each do
      @document = REXML::Element.new("people")
      @father = REXML::Element.new("Person")
      @father.attributes["name"] = "Joe"
      @son = REXML::Element.new("Child")
      @son.attributes["name"] = "Fred"
      @document.root << @father
      @document.root << @son
      @children = []
    end

    it "returns children with attribute" do
      @document.each_element_with_attribute("name") { |elem| @children << elem }
      @children[0].should == @father
      @children[1].should == @son
    end

    it "takes attribute value as second argument" do
      @document.each_element_with_attribute("name", "Fred"){ |elem| elem.should == @son }
    end

    it "takes max number of children as third argument" do
      @document.each_element_with_attribute("name", nil, 1) { |elem| @children << elem }
      @children.size.should == 1
      @children[0].should == @father
    end

    it "takes XPath filter as fourth argument" do
      @document.each_element_with_attribute("name", nil, 0, "Child"){ |elem| elem.should == @son}
    end
  end
end
