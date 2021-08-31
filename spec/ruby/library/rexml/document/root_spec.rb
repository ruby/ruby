require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Document#root" do
    it "returns document root tag name" do
      REXML::Document.new("<foo/>").root.name.should == "foo"
    end

    it "returns nil if there is not root" do
      REXML::Document.new.root.should == nil
    end
  end
end
