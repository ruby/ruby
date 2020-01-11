require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Element#comments" do
    before :each do
      @e = REXML::Element.new "root"
      @c1 = REXML::Comment.new "this is a comment"
      @c2 = REXML::Comment.new "this is another comment"
      @e << @c1
      @e << @c2
    end

    it "returns the array of comments" do
      @e.comments.should == [@c1, @c2]
    end

    it "returns a frozen object" do
      @e.comments.frozen?.should == true
    end
  end
end
