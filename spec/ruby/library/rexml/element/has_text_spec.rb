require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Element#has_text?" do

    it "returns true if element has a Text child" do
      e = REXML::Element.new("Person")
      e.text = "My text"
      e.has_text?.should be_true
    end

    it "returns false if it has no Text childs" do
      e = REXML::Element.new("Person")
      e.has_text?.should be_false
    end
  end
end
