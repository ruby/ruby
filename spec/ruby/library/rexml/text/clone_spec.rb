require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Text#clone" do
    it "creates a copy of this node" do
      text = REXML::Text.new("foo")
      text.clone.should == "foo"
      text.clone.should == text
    end
  end
end
