require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Node#parent?" do
    it "returns true for Elements" do
      e = REXML::Element.new("foo")
      e.should.parent?
    end

    it "returns true for Documents" do
      e = REXML::Document.new
      e.should.parent?
    end

    # This includes attributes, CDatas and declarations.
    it "returns false for Texts" do
      e = REXML::Text.new("foo")
      e.should_not.parent?
    end
  end
end
