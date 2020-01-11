require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#previous_element" do
    before :each do
      @a = REXML::Element.new "a"
      @b = REXML::Element.new "b"
      @c = REXML::Element.new "c"
      @a.root << @b
      @a.root << @c
    end

    it "returns previous element" do
      @a.elements["c"].previous_element.should == @b
    end

    it "returns nil on first element" do
      @a.elements["b"].previous_element.should == nil
    end
  end
end
