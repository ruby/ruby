require_relative '../../spec_helper'

describe "NilClass#to_s" do
  it "returns the string ''" do
    nil.to_s.should == ""
  end

  ruby_version_is "2.7" do
    it "returns a frozen string" do
      nil.to_s.frozen?.should == true
    end

    it "always returns the same string" do
      nil.to_s.should equal(nil.to_s)
    end
  end
end
