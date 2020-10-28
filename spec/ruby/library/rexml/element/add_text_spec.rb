require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Element#add_text" do
    before :each do
      @name = REXML::Element.new "Name"
    end

    it "adds text to an element" do
      @name.add_text "Ringo"
      @name.to_s.should == "<Name>Ringo</Name>"
    end

    it "accepts a Text" do
      @name.add_text(REXML::Text.new("Ringo"))
      @name.to_s.should == "<Name>Ringo</Name>"
    end

    it "joins the new text with the old one" do
      @name.add_text "Ringo"
      @name.add_text " Starr"
      @name.to_s.should == "<Name>Ringo Starr</Name>"
    end
  end
end
