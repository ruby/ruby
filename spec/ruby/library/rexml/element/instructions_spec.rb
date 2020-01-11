require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#instructions" do
    before :each do
      @elem = REXML::Element.new("root")
    end
    it "returns the Instruction children nodes" do
      inst = REXML::Instruction.new("xml-stylesheet", "href='headlines.css'")
      @elem << inst
      @elem.instructions.first.should == inst
    end

    it "returns an empty array if it has no Instruction children" do
      @elem.instructions.should be_empty
    end

    it "freezes the returned array" do
      @elem.instructions.frozen?.should be_true
    end
  end
end
