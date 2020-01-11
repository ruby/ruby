require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#root" do
    before :each do
      @doc  = REXML::Document.new
      @root = REXML::Element.new "root"
      @node = REXML::Element.new "node"
      @doc << @root << @node
    end

    it "returns first child on documents" do
      @doc.root.should == @root
    end

    it "returns self on root nodes" do
      @root.root.should == @root
    end

    it "returns parent's root on child nodes" do
      @node.root.should == @root
    end

    it "returns self on standalone nodes" do
      e = REXML::Element.new "Elem"         # Note that it doesn't have a parent node
      e.root.should == e
    end
  end
end
