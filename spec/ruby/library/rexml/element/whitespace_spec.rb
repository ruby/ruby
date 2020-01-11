require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#whitespace" do
    it "returns true if whitespace is respected in the element" do
      e = REXML::Element.new("root")
      e.whitespace.should be_true

      e = REXML::Element.new("root", nil, respect_whitespace: :all)
      e.whitespace.should be_true

      e = REXML::Element.new("root", nil, respect_whitespace: ["root"])
      e.whitespace.should be_true
    end

    it "returns false if whitespace is ignored inside element" do
      e = REXML::Element.new("root", nil, compress_whitespace: :all)
      e.whitespace.should be_false

      e = REXML::Element.new("root", nil, compress_whitespace: ["root"])
      e.whitespace.should be_false
    end
  end
end
