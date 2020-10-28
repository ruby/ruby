require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Text#inspect" do
    it "inspects the string attribute as a string" do
      REXML::Text.new("a text").inspect.should == "a text".inspect
    end
  end
end
