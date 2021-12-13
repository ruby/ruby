require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Attribute#value" do
    it "returns the value of the Attribute unnormalized" do
      attr = REXML::Attribute.new("name", "value")
      attr_ents = REXML::Attribute.new("name", "<&>")
      attr_empty = REXML::Attribute.new("name")

      attr.value.should == "value"
      attr_ents.value.should == "<&>"
      attr_empty.value.should == ""
    end
  end
end
