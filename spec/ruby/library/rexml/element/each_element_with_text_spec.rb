require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#each_element_with_text" do
    before :each do
      @document = REXML::Element.new("people")

      @joe = REXML::Element.new("Person")
      @joe.text = "Joe"
      @fred = REXML::Element.new("Person")
      @fred.text = "Fred"
      @another = REXML::Element.new("AnotherPerson")
      @another.text = "Fred"
      @document.root << @joe
      @document.root << @fred
      @document.root << @another
      @childs = []
    end

    it "returns childs with text" do
      @document.each_element_with_text("Joe"){|c| c.should == @joe}
    end

    it "takes max as second argument" do
      @document.each_element_with_text("Fred", 1){ |c| c.should == @fred}
    end

    it "takes XPath filter as third argument" do
      @document.each_element_with_text("Fred", 0, "Person"){ |c| c.should == @fred}
    end
  end
end
