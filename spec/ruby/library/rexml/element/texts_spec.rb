require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#texts" do

    it "returns an array of the Text children" do
      e = REXML::Element.new("root")
      e.add_text "First"
      e.add_text "Second"
      e.texts.should == ["FirstSecond"]
    end

    it "returns an empty array if it has no Text children" do
      REXML::Element.new("root").texts.should == []
    end
  end
end
