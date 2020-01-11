require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#next_element" do
    before :each do
      @a = REXML::Element.new "a"
      @b = REXML::Element.new "b"
      @c = REXML::Element.new "c"
      @a.root << @b
      @a.root << @c
    end
    it "returns next existing element" do
      @a.elements["b"].next_element.should == @c
    end

    it "returns nil on last element" do
      @a.elements["c"].next_element.should == nil
    end
  end
end
