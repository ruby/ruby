require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Document#node_type" do
    it "returns :document" do
      REXML::Document.new.node_type.should == :document
    end
  end
end
