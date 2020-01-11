require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Text#empty?" do
    it "returns true if the text is empty" do
      REXML::Text.new("").empty?.should == true
    end

    it "returns false if the text is not empty" do
      REXML::Text.new("some_text").empty?.should == false
    end
  end
end
