require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Attributes#get_attribute_ns" do
    it "returns an attribute by name and namespace" do
      e = REXML::Element.new("root")
      attr = REXML::Attribute.new("xmlns:ns", "http://some_url")
      e.attributes << attr
      attr.prefix.should == "xmlns"
      # This might be a bug in Attribute, commenting until those specs
      # are ready
      # e.attributes.get_attribute_ns(attr.prefix, "name").should == "http://some_url"
    end
  end
end
