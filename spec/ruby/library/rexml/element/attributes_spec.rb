require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Element#attributes" do
    it "returns element's Attributes" do
      p = REXML::Element.new "Person"

      name = REXML::Attribute.new("name", "John")
      attrs = REXML::Attributes.new(p)
      attrs.add name

      p.add_attribute name
      p.attributes.should == attrs
    end

    it "returns an empty hash if element has no attributes" do
      REXML::Element.new("Person").attributes.should == {}
    end
  end
end
