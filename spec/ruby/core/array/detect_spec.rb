require_relative '../../spec_helper'

ruby_version_is "4.0" do
  describe "Array#detect" do
    it "is an alias of Array#find" do
      Array.instance_method(:detect).should == Array.instance_method(:find)
    end
  end
end
