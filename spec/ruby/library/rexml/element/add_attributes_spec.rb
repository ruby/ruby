require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Element#add_attributes" do
    before :each do
      @person = REXML::Element.new "person"
      @person.attributes["name"] = "Bill"
    end

    it "adds multiple attributes from a hash" do
      @person.add_attributes({"name" => "Joe", "age" => "27"})
      @person.attributes["name"].should == "Joe"
      @person.attributes["age"].should == "27"
    end

    it "adds multiple attributes from an array" do
      attrs =  { "name" => "Joe", "age" => "27"}
      @person.add_attributes attrs.to_a
      @person.attributes["name"].should == "Joe"
      @person.attributes["age"].should == "27"
    end
  end
end
