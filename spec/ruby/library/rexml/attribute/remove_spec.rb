require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Attribute#remove" do
    before :each do
      @e = REXML::Element.new "Root"
      @attr = REXML::Attribute.new("foo", "bar")
    end

    it "deletes this Attribute from parent" do
      @e.add_attribute(@attr)
      @e.attributes["foo"].should_not == nil
      @attr.remove
      @e.attributes["foo"].should == nil
    end

    it "does not anything if element has no parent" do
      -> {@attr.remove}.should_not raise_error(Exception)
    end
  end
end
