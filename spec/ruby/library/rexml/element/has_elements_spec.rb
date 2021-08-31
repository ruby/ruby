require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Element#has_elements?" do
    before :each do
      @e = REXML::Element.new("root")
    end

    it "returns true if element has child elements" do
      child = REXML::Element.new("child")
      @e << child
      @e.has_elements?.should be_true
    end

    it "returns false if element doesn't have child elements" do
      @e.has_elements?.should be_false
    end
  end
end
