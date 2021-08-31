require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Attribute#xpath" do

    before :each do
      @e = REXML::Element.new "root"
      @attr = REXML::Attribute.new("year", "1989")
    end

    it "returns the path for Attribute" do
      @e.add_attribute @attr
      @attr.xpath.should == "root/@year"
    end

    it "raises an error if attribute has no parent" do
      -> { @attr.xpath }.should raise_error(Exception)
    end
  end
end
