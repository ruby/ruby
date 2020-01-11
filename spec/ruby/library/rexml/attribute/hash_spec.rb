require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require 'rexml/document'

  describe "REXML::Attribute#hash" do
    # These are not really complete, any idea on how to make them more
    # "testable" will be appreciated.
    it "returns a hashcode made of the name and value of self" do
      a = REXML::Attribute.new("name", "value")
      a.hash.should be_kind_of(Numeric)
      b = REXML::Attribute.new(a)
      a.hash.should == b.hash
    end
  end
end
