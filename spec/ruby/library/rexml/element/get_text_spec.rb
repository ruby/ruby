require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#get_text" do
    before :each do
      @doc = REXML::Document.new "<p>some text<b>this is bold!</b> more text</p>"
    end

    it "returns the first text child node" do
      @doc.root.get_text.value.should == "some text"
      @doc.root.get_text.should be_kind_of(REXML::Text)
    end

    it "returns text from an element matching path" do
      @doc.root.get_text("b").value.should == "this is bold!"
      @doc.root.get_text("b").should be_kind_of(REXML::Text)
    end
  end
end
