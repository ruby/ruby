require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Element#node_type" do
    it "returns :element" do
      REXML::Element.new("MyElem").node_type.should == :element
    end
  end
end
