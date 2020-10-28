require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Text#<<" do
    it "appends a string to this text node" do
      text = REXML::Text.new("foo")
      text << "bar"
      text.should == "foobar"
    end
  end
end
