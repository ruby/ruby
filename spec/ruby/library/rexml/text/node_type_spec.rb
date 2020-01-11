require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Text#node_type" do
    it "returns :text" do
      REXML::Text.new("test").node_type.should == :text
    end
  end
end
