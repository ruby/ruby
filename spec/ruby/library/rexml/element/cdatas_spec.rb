require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Element#cdatas" do
    before :each do
      @e = REXML::Element.new("Root")
    end

    it "returns the array of children cdatas" do
      c = REXML::CData.new("Primary")
      d = REXML::CData.new("Secondary")
      @e << c
      @e << d
      @e.cdatas.should == [c, d]
    end

    it "freezes the returned array" do
      @e.cdatas.should.frozen?
    end

    it "returns an empty array if element has no cdata" do
      @e.cdatas.should == []
    end
  end
end
