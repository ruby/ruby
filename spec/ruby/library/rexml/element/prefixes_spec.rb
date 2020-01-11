require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#prefixes" do
    before :each do
      doc = REXML::Document.new("<a xmlns='1' xmlns:y='2'><b/><c xmlns:z='3'/></a>")
      @elem = doc.elements["//c"]
    end

    it "returns an array of the prefixes of the namespaces" do
      @elem.prefixes.should == ["y", "z"]
    end

    it "does not include the default namespace" do
      @elem.prefixes.include?("xmlns").should == false
    end

    it "returns an empty array if no namespace was defined" do
      doc = REXML::Document.new "<root><something/></root>"
      root = doc.elements["//root"]
      root.prefixes.should == []
    end
  end
end
