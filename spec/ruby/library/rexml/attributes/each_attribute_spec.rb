require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Attributes#each_attribute" do
    it "iterates over the attributes yielding actual Attribute objects" do
      e = REXML::Element.new("root")
      name = REXML::Attribute.new("name", "Joe")
      ns_uri = REXML::Attribute.new("xmlns:ns", "http://some_uri")
      e.add_attribute name
      e.add_attribute ns_uri

      attributes = []

      e.attributes.each_attribute do |attr|
        attributes << attr
      end

      attributes = attributes.sort_by {|a| a.name }
      attributes.first.should == name
      attributes.last.should == ns_uri
    end
  end
end
